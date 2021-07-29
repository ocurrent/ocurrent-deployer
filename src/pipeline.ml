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

module Cluster = struct
  module Ci3_docker = Current_docker.Default
  module Ci4_docker = Current_docker.Make(struct let docker_context = Some "ci4" end)
  module Ci6_docker = Current_docker.Make(struct let docker_context = Some "docsci" end)
  module Toxis_docker = Current_docker.Make(struct let docker_context = Some "toxis" end)
  module Autumn_docker = Current_docker.Make(struct let docker_context = Some "autumn-current-bench" end)
  module Ocamlorg_docker = Current_docker.Make(struct let docker_context = Some "ocaml-www1" end)

  type build_info = {
    sched : Current_ocluster.t;
    dockerfile : [`Contents of string Current.t | `Path of string];
    options : Cluster_api.Docker.Spec.options;
    archs : arch list;
  }

  type service = [
    | `Toxis of string
    | `Ci3 of string
    | `Ci4 of string
    | `Ci6 of string
    | `Autumn of string
    | `Ocamlorg_sw of (string * string) list
  ]

  type deploy_info = {
    hub_id : Cluster_api.Docker.Image_id.t;
    services : service list;
  }

  (* Build [src/dockerfile] as a Docker service. *)
  let build { sched; dockerfile; options; archs } src =
    let src = Current.map (fun x -> [x]) src in
    let build_arch arch = Current_ocluster.build sched ~options ~pool:(pool_id arch) ~src dockerfile in
    Current.all (List.map build_arch archs)

  let name info = Cluster_api.Docker.Image_id.to_string info.hub_id

  let no_schedule = Current_cache.Schedule.v ()

  let pull_and_serve (module D : Current_docker.S.DOCKER) ~name op repo_id =
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
    match op with
    | `Service -> D.service ~name ~image ()
    | `Compose contents ->
        let contents = Current.map (fun image ->
          Caddy.replace_hash_var ~hash:(D.Image.hash image) contents) image in
        D.compose ~name ~contents ()

  let deploy { sched; dockerfile; options; archs } { hub_id; services } src =
    let src = Current.map (fun x -> [x]) src in
    let target_label = Cluster_api.Docker.Image_id.repo hub_id |> String.map (function '/' | ':' -> '-' | c -> c) in
    let build_arch arch =
      let pool = pool_id arch in
      let tag = Printf.sprintf "live-%s-%s" target_label pool in
      let push_target = Cluster_api.Docker.Image_id.v ~repo:push_repo ~tag in
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
            | `Ci3 name -> pull_and_serve (module Ci3_docker) ~name `Service multi_hash
            | `Ci4 name -> pull_and_serve (module Ci4_docker) ~name `Service multi_hash
            | `Ci6 name -> pull_and_serve (module Ci6_docker) ~name `Service multi_hash
            | `Toxis name -> pull_and_serve (module Toxis_docker) ~name `Service multi_hash
            | `Autumn name -> pull_and_serve (module Autumn_docker) ~name `Service multi_hash
            | `Ocamlorg_sw domains ->
              let name = Cluster_api.Docker.Image_id.tag hub_id in
              let contents = Caddy.compose {Caddy.name; domains} in
              pull_and_serve (module Ocamlorg_docker) ~name (`Compose contents) multi_hash
          )
        |> Current.all
end
module Cluster_build = Build.Make(Cluster)

(* [web_ui collapse_value] is a URL back to the deployment service, for links
   in status messages. *)
let web_ui =
  let base = Uri.of_string "https://deploy.ci3.ocamllabs.io/" in
  fun repo -> Uri.with_query' base ["repo", repo]

let docker ?(archs=[`Linux_x86_64]) ?(options=Cluster_api.Docker.Spec.defaults) ~sched dockerfile targets =
  let build_info = { Cluster.sched; dockerfile = `Path dockerfile; options; archs } in
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

let filter_list filter items =
  match filter with
  | None -> items
  | Some filter ->
    let items =
      items |> List.filter @@ fun (org, name, _) ->
      filter { Current_github.Repo_id.owner = Build.account org; name }
    in
    if items = [] then Fmt.failwith "No repository matches the filter!"
    else items

let include_git = { Cluster_api.Docker.Spec.defaults with include_git = true }

(* This is a list of GitHub repositories to monitor.
   For each one, it lists the builds that are made from that repository.
   For each build, it says which which branch gives the desired live version of
   the service, and where to deloy it. *)
let v ?app ?notify:channel ?filter ~sched ~staging_auth () =
  let ocurrent = Build.org ?app ~account:"ocurrent" 12497518 in
  let ocaml = Build.org ?app ~account:"ocaml" 18513252 in
  let build (org, name, builds) = Cluster_build.repo ?channel ~web_ui ~org ~name builds in
  let sched = Current_ocluster.v ~timeout ?push_auth:staging_auth sched in
  let docker = docker ~sched in
  Current.all @@ List.map build @@ filter_list filter [
    ocurrent, "ocurrent-deployer", [
      docker "Dockerfile"     ["live-ci3",   "ocurrent/ci.ocamllabs.io-deployer:live-ci3",   [`Ci3 "deployer_deployer"]];
      docker "Dockerfile"     ["live-toxis", "ocurrent/ci.ocamllabs.io-deployer:live-toxis", [`Toxis "infra_deployer"]];
    ];
    ocurrent, "ocaml-ci", [
      docker "Dockerfile"     ["live-engine", "ocurrent/ocaml-ci-service:live", [`Toxis "ocaml-ci_ci"]];
      docker "Dockerfile.web" ["live-www",    "ocurrent/ocaml-ci-web:live",     [`Toxis "ocaml-ci_web"];
                               "staging-www", "ocurrent/ocaml-ci-web:staging",  [`Toxis "test-www"]];
    ];
    ocurrent, "docker-base-images", [
      docker "Dockerfile"     ["live", "ocurrent/base-images:live", [`Toxis "base-images_builder"]];
    ];      
    ocurrent, "ocluster", [
      docker "Dockerfile"        ["live-scheduler", "ocurrent/ocluster-scheduler:live", []];
      docker "Dockerfile.worker" ["live-worker",    "ocurrent/ocluster-worker:live", []]
        ~archs:[`Linux_x86_64; `Linux_arm64; `Linux_ppc64];
    ];
    ocurrent, "opam-repo-ci", [
      docker "Dockerfile"     ["live", "ocurrent/opam-repo-ci:live", [`Ci3 "opam-repo-ci_opam-repo-ci"]];
      docker "Dockerfile.web" ["live-web", "ocurrent/opam-repo-ci-web:live", [`Ci3 "opam-repo-ci_opam-repo-ci-web"]];
    ];
    ocurrent, "ocaml-multicore-ci", [
      docker "Dockerfile"     ["live", "ocurrent/multicore-ci:live", [`Ci4 "infra_multicore-ci"]];
      docker "Dockerfile.web" ["live-web", "ocurrent/multicore-ci-web:live", [`Ci4 "infra_multicore-ci-web"]];
    ];
    ocurrent, "ocaml-docs-ci", [
      docker "Dockerfile"                 ["live", "ocurrent/docs-ci:live", [`Ci6 "infra_docs-ci"]];
      docker "docker/init/Dockerfile"     ["live", "ocurrent/docs-ci-init:live", [`Ci6 "infra_init"]];
      docker "docker/storage/Dockerfile"  ["live", "ocurrent/docs-ci-storage-server:live", [`Ci6 "infra_storage-server"]];
      docker "Dockerfile.web"             ["live-web", "ocurrent/docs-ci-web:live", [`Ci6 "infra_docs-ci-web"]];
    ];
    ocurrent, "current-bench", [
      docker "pipeline/Dockerfile" ["live", "ocurrent/current-bench-pipeline:live", [`Autumn "current-bench_pipeline"]];
      docker "frontend/Dockerfile" ["live", "ocurrent/current-bench-frontend:live", [`Autumn "current-bench_frontend"]];
    ];
    ocaml, "ocaml.org", [
      docker "Dockerfile.deploy"  ["master", "ocurrent/ocaml.org:live",    [`Ocamlorg_sw ["www.ocaml.org", "51.159.79.75"; "ocaml.org", "51.159.78.124"]]]
        ~options:include_git;
      docker "Dockerfile.staging" ["staging","ocurrent/ocaml.org:staging", [`Ocamlorg_sw ["staging.ocaml.org", "51.159.79.64"]]]
        ~options:include_git;
    ];
    ocaml, "v3.ocaml.org", [
      docker "Dockerfile" ["master", "ocurrent/v3.ocaml.org:live", []]
    ];
    ocaml, "v3.ocaml.org-server", [
      docker "Dockerfile" ["main", "ocurrent/v3.ocaml.org-server:live", []]
    ];
  ]
