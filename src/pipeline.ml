open Current.Syntax

module Github = Current_github

let timeout = Duration.of_min 50    (* Max build time *)

let password_path = "/run/secrets/ocurrent-hub"

let push_repo = "ocurrentbuilder/staging"

let auth =
  if Sys.file_exists password_path then (
    let ch = open_in_bin password_path in
    let len = in_channel_length ch in
    let password = really_input_string ch len |> String.trim in
    close_in ch;
    Some ("ocurrent", password)
  ) else (
    Fmt.pr "Password file %S not found; images will not be pushed to hub@." password_path;
    None
  )

let or_fail = function
  | Ok x -> x
  | Error (`Msg m) -> failwith m

type arch = [
  | `Linux_arm64
  | `Linux_x86_64
  | `Linux_ppc64
]

let pool_id : arch -> string = function
  | `Linux_arm64 -> "linux-arm64"
  | `Linux_x86_64 -> "linux-x86_64"
  | `Linux_ppc64 -> "linux-ppc64"

module Packet_unikernel = struct
  (* Mirage unikernels running on packet.net *)

  module Docker = Current_docker.Default

  type build_info = {
    dockerfile : string;
    target : string;
    args : string list;
  }

  type deploy_info = {
    service : string;
  }

  let build_image { dockerfile; target; args } src =
    let src = Current_git.fetch src in
    let args = ("TARGET=" ^ target) :: args in
    let build_args = List.map (fun x -> ["--build-arg"; x]) args |> List.concat in
    let dockerfile = Current.return (`File (Fpath.v dockerfile)) in
    Docker.build (`Git src)
      ~build_args
      ~dockerfile
      ~label:target
      ~pull:true
      ~timeout

  let build info src = Current.ignore_value (build_image info src)

  let name { service } = service

  (* Deployment *)

  module Mirage_m1_a = Mirage.Make(Docker)

  let mirage_host_ssh = "root@147.75.204.215"

  let deploy build_info { service } src =
    let image = build_image build_info src in
    (* We tag the image to prevent docker prune from removing it.
       Otherwise, if we later deploy a new (bad) version and need to roll back quickly,
       we may find the old version isn't around any longer. *)
    let tag = "mirage-" ^ service in
    Current.all [
      Docker.tag ~tag image;
      Mirage_m1_a.deploy ~name:service ~ssh_host:mirage_host_ssh image;
    ]
end
module Build_unikernel = Build.Make(Packet_unikernel)

module Cluster = struct
  module Ci3_docker = Current_docker.Default
  module Ci4_docker = Current_docker.Make(struct let docker_context = Some "ci4" end)
  module Ci6_docker = Current_docker.Make(struct let docker_context = Some "docsci" end)
  module Toxis_docker = Current_docker.Make(struct let docker_context = Some "toxis" end)

  type build_info = {
    sched : Current_ocluster.t;
    dockerfile : [`Contents of string Current.t | `Path of string];
    archs : arch list;
  }

  type deploy_info = {
    hub_id : Cluster_api.Docker.Image_id.t;
    services : ([`Toxis | `Ci3 | `Ci4 | `Ci6] * string) list;
  }

  (* Build [src/dockerfile] as a Docker service. *)
  let build { sched; dockerfile; archs } src =
    let src = Current.map (fun x -> [x]) src in
    let options = Cluster_api.Docker.Spec.defaults in
    let build_arch arch = Current_ocluster.build sched ~options ~pool:(pool_id arch) ~src dockerfile in
    Current.all (List.map build_arch archs)

  let name info = Cluster_api.Docker.Image_id.to_string info.hub_id

  let no_schedule = Current_cache.Schedule.v ()

  let pull_and_serve (module D : Current_docker.S.DOCKER) ~name repo_id =
    let image =
      Current.component "pull" |>
      let> repo_id = repo_id in
      Current_docker.Raw.pull repo_id
      ~docker_context:D.docker_context
      ~schedule:no_schedule
      |> Current.Primitive.map_result (Result.map (fun raw_image ->
          D.Image.of_hash (Current_docker.Raw.Image.hash raw_image)
        ))
    in
    D.service ~name ~image ()

  let deploy { sched; dockerfile; archs } { hub_id; services } src =
    let src = Current.map (fun x -> [x]) src in
    let target_label = Cluster_api.Docker.Image_id.repo hub_id |> String.map (function '/' | ':' -> '-' | c -> c) in
    let build_arch arch =
      let pool = pool_id arch in
      let tag = Printf.sprintf "live-%s-%s" target_label pool in
      let push_target = Cluster_api.Docker.Image_id.v ~repo:push_repo ~tag in
      let options = Cluster_api.Docker.Spec.defaults in
      Current_ocluster.build_and_push sched ~options ~push_target ~pool ~src dockerfile
    in
    let images = List.map build_arch archs in
    match auth with
    | None -> Current.all (Current.fail "No auth configured; can't push final image" :: List.map Current.ignore_value images)
    | Some auth ->
      let multi_hash = Current_docker.push_manifest ~auth images ~tag:(Cluster_api.Docker.Image_id.to_string hub_id) in
      match services with
      | [] -> Current.ignore_value multi_hash
      | services ->
        services
        |> List.map (function
            | `Ci3, name -> pull_and_serve (module Ci3_docker) ~name multi_hash
            | `Ci4, name -> pull_and_serve (module Ci4_docker) ~name multi_hash
            | `Ci6, name -> pull_and_serve (module Ci6_docker) ~name multi_hash
            | `Toxis, name -> pull_and_serve (module Toxis_docker) ~name multi_hash
          )
        |> Current.all
end
module Cluster_build = Build.Make(Cluster)

(* [web_ui collapse_value] is a URL back to the deployment service, for links
   in status messages. *)
let web_ui =
  let base = Uri.of_string "https://deploy.ci3.ocamllabs.io/" in
  fun repo -> Uri.with_query' base ["repo", repo]

let docker ?(archs=[`Linux_x86_64]) ~sched dockerfile targets =
  let build_info = { Cluster.sched; dockerfile = `Path dockerfile; archs } in
  let deploys =
    targets
    |> List.map (fun (branch, target, services) ->
        branch, { Cluster.
                  hub_id = Cluster_api.Docker.Image_id.of_string target |> or_fail;
                  services
                }
      )
  in
  (build_info, deploys)

let _unikernel dockerfile ~target args services =
  let build_info = { Packet_unikernel.dockerfile; target; args } in
  let deploys =
    services
    |> List.map (fun (branch, service) -> branch, { Packet_unikernel.service }) in
  (build_info, deploys)

(* This is a list of GitHub repositories to monitor.
   For each one, it lists the builds that are made from that repository.
   For each build, it says which which branch gives the desired live version of
   the service, and where to deloy it. *)
let v ~app ~notify:channel ~sched ~staging_auth () =
  let ocurrent = Build.org ~app ~account:"ocurrent" 12497518 in
  let docker_services =
    let build (org, name, builds) = Cluster_build.repo ~channel ~web_ui ~org ~name builds in
    let sched = Current_ocluster.v ~timeout ?push_auth:staging_auth sched in
    let docker = docker ~sched in
    Current.all @@ List.map build [
      ocurrent, "ocurrent-deployer", [
        docker "Dockerfile"     ["live-ci3", "ocurrent/ci.ocamllabs.io-deployer:live-ci3", [`Ci3, "deployer_deployer"]];
      ];
      ocurrent, "ocaml-ci", [
        docker "Dockerfile"     ["live-engine", "ocurrent/ocaml-ci-service:live", [`Toxis, "ocaml-ci_ci"]];
        docker "Dockerfile.web" ["live-www",    "ocurrent/ocaml-ci-web:live",     [`Toxis, "ocaml-ci_web"];
                                 "staging-www", "ocurrent/ocaml-ci-web:staging",  [`Toxis, "test-www"]];
      ];
      ocurrent, "docker-base-images", [
        docker "Dockerfile"     ["live", "ocurrent/base-images:live", [`Toxis, "base-images_builder"]];
      ];      
      ocurrent, "ocluster", [
        docker "Dockerfile"        ["live-scheduler", "ocurrent/ocluster-scheduler:live", []];
        docker "Dockerfile.worker" ["live-worker",    "ocurrent/ocluster-worker:live", []]
          ~archs:[`Linux_x86_64; `Linux_arm64; `Linux_ppc64];
      ];
      ocurrent, "opam-repo-ci", [
        docker "Dockerfile"     ["live", "ocurrent/opam-repo-ci:live", [`Ci3, "opam-repo-ci_opam-repo-ci"]];
        docker "Dockerfile.web" ["live-web", "ocurrent/opam-repo-ci-web:live", [`Ci3, "opam-repo-ci_opam-repo-ci-web"]];
      ];
      ocurrent, "ocaml-multicore-ci", [
        docker "Dockerfile"     ["live", "ocurrent/multicore-ci:live", [`Ci4, "infra_multicore-ci"]];
        docker "Dockerfile.web" ["live-web", "ocurrent/multicore-ci-web:live", [`Ci4, "infra_multicore-ci-web"]];
      ];
      ocurrent, "ocaml-docs-ci", [
        docker "Dockerfile"                 ["live", "ocurrent/docs-ci:live", [`Ci6, "infra_docs-ci"]];
        docker "docker/init/Dockerfile"     ["live", "ocurrent/docs-ci-init:live", [`Ci6, "infra_init"]];
        docker "docker/storage/Dockerfile"  ["live", "ocurrent/docs-ci-storage-server:live", [`Ci6, "infra_storage-server"]];
        docker "docker/git-http/Dockerfile" ["live", "ocurrent/docs-ci-git-http:live", [`Ci6, "infra_git-http"]];
        docker "docker/git-http-website/Dockerfile" 
                                            ["live", "ocurrent/docs-ci-git-http-website:live", [`Ci6, "infra_git-http-tailwind-website"; 
                                                                                                `Ci6, "infra_git-http-classic-website"]];
        docker "Dockerfile.web"             ["live-web", "ocurrent/docs-ci-web:live", [`Ci6, "infra_docs-ci-web"]];
      ];
    ]
  and mirage_unikernels =
    let build (org, name, builds) = Build_unikernel.repo ~channel ~web_ui ~org ~name builds in
    Current.all @@ List.map build [
    ]
  in
  Current.all [ docker_services; mirage_unikernels ]
