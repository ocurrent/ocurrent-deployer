(* Different Deployer pipelines available. *)
module Flavour = struct
  type t = [`Tarides | `OCaml | `Toxis ]
  let cmdliner =
    let open Cmdliner in
    let flavours = ["tarides", `Tarides
                   ; "ocaml", `OCaml
                   ; "toxis", `Toxis
                   ]
    in
    let enum_alts = Arg.doc_alts_enum flavours in
    let doc = Format.asprintf "Pipeline flavour to run. $(docv) must be %s." enum_alts
    in
    Arg.(required & opt (some & enum flavours) None &
         info ["flavour"] ~doc ~docv:"FLAVOUR"
      )
end

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
  | `Linux_s390x
  | `Linux_riscv64
]

let pool_id : arch -> string = function
  | `Linux_arm64 -> "linux-arm64"
  | `Linux_x86_64 -> "linux-x86_64"
  | `Linux_ppc64 -> "linux-ppc64"
  | `Linux_s390x -> "linux-s390x"
  | `Linux_riscv64 -> "linux-riscv64"

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

  let build info ?additional_build_args:_ (_:Github.Repo_id.t) src  = Current.ignore_value (build_image info src)

  let name { service } = service

  (* Deployment *)

  module Mirage_m1_a = Mirage.Make(Docker)

  let mirage_host_ssh = "root@147.75.84.37"

  let deploy build_info { service } ?additional_build_args:_ src =
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
  (* Strings here represent the docker context to use. *)
  module Ci3_docker = Current_docker.Default
  module Ci4_docker = Current_docker.Make(struct let docker_context = Some "ci4.ocamllabs.io" end)
  module Docs_docker = Current_docker.Make(struct let docker_context = Some "docs.ci.ocaml.org" end)
  module Toxis_docker = Current_docker.Make(struct let docker_context = Some "ci.ocamllabs.io" end)
  module Tezos_docker = Current_docker.Make(struct let docker_context = Some "tezos.ci.dev" end)
  module Ocamlorg_docker = Current_docker.Make(struct let docker_context = Some "ocaml-www1" end)
  module V3ocamlorg_docker = Current_docker.Make(struct let docker_context = Some "v3.ocaml.org" end)
  module Stagingocamlorg_docker = Current_docker.Make(struct let docker_context = Some "staging.ocaml.org" end)
  module Cimirage_docker = Current_docker.Make(struct let docker_context = Some "ci.mirage.io" end)
  module Opamocamlorg_docker = Current_docker.Make(struct let docker_context = Some "opam-3.ocaml.org" end)
  module V2ocamlorg_docker = Current_docker.Make(struct let docker_context = Some "v2.ocaml.org" end)
  module Ocamlorg_images = Current_docker.Make(struct let docker_context = Some "ci3.ocamllabs.io" end)
  module Docker_aws = Current_docker.Make(struct let docker_context = Some "awsecs" end)
  module Deploycamlorg_docker = Current_docker.Default

  type build_info = {
    sched : Current_ocluster.t;
    dockerfile : [`Contents of string Current.t | `Path of string];
    options : Cluster_api.Docker.Spec.options;
    archs : arch list;
  }

  type service = [
    (* Services on deploy.ci3.ocamllabs.io *)
    | `Toxis of string
    | `Tezos of string
    | `Ci3 of string
    | `Ci4 of string
    | `Docs of string
    | `Cimirage of string

    (* Services on deploy.ci.ocaml.org. *)
    | `Ocamlorg_deployer of string             (* OCurrent deployer @ deploy.ci.ocaml.org *)
    | `OCamlorg_v2 of (string * string) list   (* OCaml website @ v2.ocaml.org *)
    | `Ocamlorg_opam of string                 (* Opam website @ opam-3.ocaml.org *)
    | `Ocamlorg_images of string               (* Base Image builder @ images.ci.ocaml.org *)
    | `V3ocamlorg_cl of string                 (* OCaml website @ v3a.ocaml.org aka www.ocaml.org *)
    | `Stagingocamlorg_cl of string            (* Staging OCaml website @ staging.ocaml.org *)
    | `Aws_ecs of Aws.t                        (* Amazon Web Services - Elastic Container Service *)
  ]

  type deploy_info = {
    hub_id : Cluster_api.Docker.Image_id.t;
    services : service list;
  }

  let get_job_id x =
    let+ md = Current.Analysis.metadata x in
    match md with
    | Some { Current.Metadata.job_id; _ } -> job_id
    | None -> None

  (* Build [src/dockerfile] as a Docker service. *)
  let build { sched; dockerfile; options; archs } ?(additional_build_args=Current.return []) repo src : unit Current.t =
    Current.component "HEADs" |>
    let** additional_build_args = additional_build_args in
    let options = { options with build_args = additional_build_args @ options.build_args } in
    let build_arch arch =
      let* src = src in
      let build = Current_ocluster.build sched ~options ~pool:(pool_id arch) ~src:(Current.return [src]) dockerfile in
      let hash = Current_git.Commit_id.hash src in
      let () = Logs.info (fun f -> f "Building arch: %s repo: %s hash: %s" (pool_id arch) (Fmt.str("%s/%s") repo.Github.Repo_id.owner repo.name) hash) in
      let+ job_id = get_job_id build in
      let job_str = match job_id with | Some x -> x | None -> "None" in
      let () = Logs.info (fun f -> f "Recording repo: %s hash: %s job: %s" (Fmt.str("%s/%s") repo.owner repo.name) hash job_str) in
      Index.record ~repo ~hash [("build", job_id)]
    in
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
        D.compose_cli ~name ~contents ~detach:true ()
    | `Compose_cli contents ->
        let contents = Current.map (fun hash ->
          Aws.replace_hash_var ~hash contents) repo_id in
        D.compose_cli ~name ~contents ~detach:false ()

  let deploy { sched; dockerfile; options; archs } { hub_id; services } ?(additional_build_args=Current.return []) src =
    let src = Current.map (fun x -> [x]) src in
    let target_label = Cluster_api.Docker.Image_id.repo hub_id |> String.map (function '/' | ':' -> '-' | c -> c) in
    Current.component "HEADs" |>
    let** additional_build_args = additional_build_args in
    let options = { options with build_args = additional_build_args @ options.build_args } in
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
            (* ci3.ocamllabs.io *)
            | `Ci3 name -> pull_and_serve (module Ci3_docker) ~name `Service multi_hash
            | `Ci4 name -> pull_and_serve (module Ci4_docker) ~name `Service multi_hash
            | `Docs name -> pull_and_serve (module Docs_docker) ~name `Service multi_hash
            | `Toxis name -> pull_and_serve (module Toxis_docker) ~name `Service multi_hash
            | `Tezos name -> pull_and_serve (module Tezos_docker) ~name `Service multi_hash
            | `Cimirage name -> pull_and_serve (module Cimirage_docker) ~name `Service multi_hash

            (* ocaml.org *)
            | `Ocamlorg_deployer name -> pull_and_serve (module Deploycamlorg_docker) ~name `Service multi_hash
            | `OCamlorg_v2 domains ->
              let name = Cluster_api.Docker.Image_id.tag hub_id in
              let contents = Caddy.compose {Caddy.name; domains} in
              pull_and_serve (module V2ocamlorg_docker) ~name (`Compose contents) multi_hash
            | `Ocamlorg_opam name ->
              pull_and_serve (module Opamocamlorg_docker) ~name `Service multi_hash
            | `Ocamlorg_images name -> pull_and_serve (module Ocamlorg_images) ~name `Service multi_hash
            | `V3ocamlorg_cl name -> pull_and_serve (module V3ocamlorg_docker) ~name `Service multi_hash
            | `Stagingocamlorg_cl name -> pull_and_serve (module Stagingocamlorg_docker) ~name `Service multi_hash
            | `Aws_ecs project ->
              let contents = Aws.compose project in
              pull_and_serve (module Docker_aws) ~name:(project.name ^ "-" ^ project.branch) (`Compose_cli contents) multi_hash
          )
        |> Current.all
end
module Cluster_build = Build.Make(Cluster)

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
    items |> List.filter @@ fun (org, name, _) ->
    filter { Current_github.Repo_id.owner = Build.account org; name }

let include_git = { Cluster_api.Docker.Spec.defaults with include_git = true }

let build_kit (v : Cluster_api.Docker.Spec.options) = { v with buildkit = true }

(* This is a list of GitHub repositories to monitor.
   For each one, it lists the builds that are made from that repository.
   For each build, it says which which branch gives the desired live version of
   the service, and where to deploy it. *)
let tarides ?app ?notify:channel ?filter ~sched ~staging_auth () =
  (* [web_ui collapse_value] is a URL back to the deployment service, for links
     in status messages. *)
  let web_ui =
    let base = Uri.of_string "https://deploy.ci3.ocamllabs.io/" in
    fun repo -> Uri.with_query' base ["repo", repo] in

  let ocurrent = Build.org ?app ~account:"ocurrent" 12497518 in
  let ocaml_bench = Build.org ?app ~account:"ocaml-bench" 19839896 in

  let build (org, name, builds) = Cluster_build.repo ?channel ~web_ui ~org ~name builds in
  let sched_regular = Current_ocluster.v ~timeout ?push_auth:staging_auth sched in

  let docker = docker ~sched:sched_regular in

  Current.all @@ List.map build @@ filter_list filter [
    ocurrent, "ocurrent-deployer", [
      docker "Dockerfile"     ["live-ci3",   "ocurrent/ci.ocamllabs.io-deployer:live-ci3",   [`Ci3 "deployer_deployer"]];
      docker "Dockerfile"     ["live-toxis", "ocurrent/ci.ocamllabs.io-deployer:live-toxis", [`Toxis "infra_deployer"]];
    ];
    ocurrent, "ocaml-ci", [
      docker "Dockerfile"     ["live-engine", "ocurrent/ocaml-ci-service:live", [`Toxis "ocaml-ci_ci"]];
      docker "Dockerfile.gitlab" ["live-engine", "ocurrent/ocaml-ci-gitlab-service:live", [`Toxis "ocaml-ci_gitlab"]];
      docker "Dockerfile.web" ["live-www",    "ocurrent/ocaml-ci-web:live",     [`Toxis "ocaml-ci_web"];
                               "staging-www", "ocurrent/ocaml-ci-web:staging",  [`Toxis "test-www"]];
    ];
    ocurrent, "ocluster", [
      docker "Dockerfile"        ["live-scheduler", "ocurrent/ocluster-scheduler:live", []] 
        ~archs:[`Linux_x86_64; `Linux_arm64] ~options:include_git;
      docker "Dockerfile.worker" ["live-worker",    "ocurrent/ocluster-worker:live", []]
        ~archs:[`Linux_x86_64; `Linux_arm64; `Linux_ppc64; `Linux_s390x; `Linux_riscv64] ~options:include_git;
    ];
    ocurrent, "opam-repo-ci", [
      docker "Dockerfile"     ["live", "ocurrent/opam-repo-ci:live", [`Ci3 "opam-repo-ci_opam-repo-ci"]];
      docker "Dockerfile.web" ["live-web", "ocurrent/opam-repo-ci-web:live", [`Ci3 "opam-repo-ci_opam-repo-ci-web"]];
    ];
    ocurrent, "ocaml-multicore-ci", [
      docker "Dockerfile"     ["live", "ocurrent/multicore-ci:live", [`Ci4 "infra_multicore-ci"]];
      docker "Dockerfile.web" ["live-web", "ocurrent/multicore-ci-web:live", [`Ci4 "infra_multicore-ci-web"]];
    ];
    ocurrent, "ocurrent.org", [
      docker "Dockerfile"     ["live-engine", "ocurrent/ocurrent.org:live-engine", [`Ci3 "ocurrent_org_watcher"]];
    ];

    ocaml_bench, "sandmark-nightly", [
      docker "Dockerfile" ["main", "ocurrent/sandmark-nightly:live", [`Ci3 "sandmark_sandmark"]] 
      ~options:include_git;
    ];

    ocurrent, "mirage-ci", [
        docker "Dockerfile" ["live", "ocurrent/mirage-ci:live", [`Cimirage "infra_mirage-ci"]]
        ~options:(include_git |> build_kit)
      ];
    ocurrent, "solver-service", [
      docker "Dockerfile" ["live", "ocurrent/solver-service:live", [`Ci4 "infra_solver-service"]]
        ~archs:[`Linux_x86_64; `Linux_arm64; `Linux_ppc64]
    ]
  ]

(* This is a list of GitHub repositories to monitor.
   For each one, it lists the builds that are made from that repository.
   For each build, it says which which branch gives the desired live version of
   the service, and where to deploy it. *)
let ocaml_org ?app ?notify:channel ?filter ~sched ~staging_auth () =
  (* [web_ui collapse_value] is a URL back to the deployment service, for links
     in status messages. *)
  let web_ui =
    let base = Uri.of_string "https://deploy.ci.ocaml.org" in
    fun repo -> Uri.with_query' base ["repo", repo] in
  let ocurrent = Build.org ?app ~account:"ocurrent" 23342906 in
  let ocaml = Build.org ?app ~account:"ocaml" 23711648 in
  let ocaml_opam = Build.org ?app ~account:"ocaml-opam" 23690708 in

  let build ?additional_build_args (org, name, builds) =
    Cluster_build.repo ?channel ?additional_build_args ~web_ui ~org ~name builds in

  let docker_with_timeout timeout =
    docker ~sched:(Current_ocluster.v ~timeout ?push_auth:staging_auth sched)
  in

  let sched = Current_ocluster.v ~timeout ?push_auth:staging_auth sched in
  let docker = docker ~sched in
  let pipelines = filter_list filter [
    ocurrent, "ocurrent-deployer", [
      docker "Dockerfile"     ["live-ocaml-org", "ocurrent/ci.ocamllabs.io-deployer:live-ocaml-org", [`Ocamlorg_deployer "infra_deployer"]];
    ];

    ocaml, "ocaml.org", [
      (* New V3 ocaml.org website. *)
      docker "Dockerfile" ["main", "ocurrent/v3.ocaml.org-server:live", [`V3ocamlorg_cl "infra_www";
                                                                         `Aws_ecs {name = "v3a"; branch = "live"; vcpu = 0.5; memory = 2048; storage = None; replicas = 2; command = None; port = 8080; certificate = "arn:aws:acm:us-east-1:867081712685:certificate/24cde0e9-42c0-41ef-99d8-0fe8db462f36"}]];
      (* Staging branch for ocaml.org website. *)
      docker "Dockerfile" ["staging", "ocurrent/v3.ocaml.org-server:staging", [`Stagingocamlorg_cl "infra_www";
                                                                               `Aws_ecs {name = "v3a"; branch = "staging"; vcpu = 0.5; memory = 2048; storage = None; replicas = 1; command = None; port = 8080; certificate = "arn:aws:acm:us-east-1:867081712685:certificate/9647db34-004d-43d2-9102-accf6e09c63a"}]]
    ];

    ocaml, "v2.ocaml.org", [
      (* Backup of existing ocaml.org website. *)
      docker "Dockerfile.deploy"  ["master", "ocurrent/v2.ocaml.org:live", [`OCamlorg_v2 ["v2.ocaml.org", "10.197.242.33"]]] ~options:include_git;
    ];

    ocurrent, "docker-base-images", [
        (* Docker base images @ images.ci.ocaml.org *)
        docker "Dockerfile"     ["live", "ocurrent/base-images:live", [`Ocamlorg_images "base-images_builder"]];
      ];

    ocurrent, "ocaml-docs-ci", [
        docker "Dockerfile"                 ["live", "ocurrent/docs-ci:live", [`Docs "infra_docs-ci"]];
        docker "docker/init/Dockerfile"     ["live", "ocurrent/docs-ci-init:live", [`Docs "infra_init"]];
        docker "docker/storage/Dockerfile"  ["live", "ocurrent/docs-ci-storage-server:live", [`Docs "infra_storage-server"]];
      ];
    ]  in

  let head_of repo (id: Github.Api.Ref.t) =
    match Build.api ocaml_opam with
    | Some api ->
      let (id': Github.Api.Ref.id) = match id with
      | `Ref x -> `Ref x
      | `PR pri -> `PR pri.id
      in
      Current.map Github.Api.Commit.id @@ Github.Api.head_of api repo id'
    | None -> Github.Api.Anonymous.head_of repo id
  in

  let additional_build_args =
    let+ opam_repository_commit =
      head_of { Github.Repo_id.owner = "ocaml"; name = "opam-repository" } @@ `Ref "refs/heads/master"
    and+ platform_blog_commit =
      head_of { Github.Repo_id.owner = "ocaml"; name = "platform-blog" } @@ `Ref "refs/heads/master" in
    ["OPAM_GIT_SHA=" ^ Current_git.Commit_id.hash opam_repository_commit;
     "BLOG_GIT_SHA=" ^ Current_git.Commit_id.hash platform_blog_commit]
  in

  let opam_repository_pipeline = filter_list filter [
    ocaml_opam, "opam2web", [
      docker_with_timeout (Duration.of_min 240)
        "Dockerfile" [ "live", "ocurrent/opam.ocaml.org:live", [`Ocamlorg_opam "infra_opam_live";
                                                                `Aws_ecs {name = "opam3"; branch = "live"; vcpu = 0.25; memory = 512; storage = Some 50; replicas = 2; command = Some "--root /usr/share/caddy"; port = 80; certificate = "arn:aws:acm:us-east-1:867081712685:certificate/941be8db-4733-49c9-b634-43ff0537890c"}]
                     ; "live-staging", "ocurrent/opam.ocaml.org:staging", [`Ocamlorg_opam "infra_opam_staging";
                                                                           `Aws_ecs {name = "opam3"; branch = "staging"; vcpu = 0.25; memory = 512; storage = Some 50; replicas = 1; command = Some "--root /usr/share/caddy"; port = 80; certificate = "arn:aws:acm:us-east-1:867081712685:certificate/954e46c1-33fe-405d-ba4b-49ca189f050b"}]]
        ~options:(include_git |> build_kit)
        ~archs:[`Linux_arm64; `Linux_x86_64]
    ]
  ]
  in
  Current.all (List.append
                 (List.map (fun x -> build ~additional_build_args x) opam_repository_pipeline)
                 (List.map build pipelines))

let unikernel dockerfile ~target args services =
  let build_info = { Packet_unikernel.dockerfile; target; args } in
  let deploys =
    services
    |> List.map (fun (branch, service) -> branch, { Packet_unikernel.service }) in
  (build_info, deploys)

let toxis ?app ?notify:channel () =
  (* [web_ui collapse_value] is a URL back to the deployment service, for links
     in status messages. *)
  let web_ui =
    let base = Uri.of_string "https://deploy.ocamllabs.io/" in
    fun repo -> Uri.with_query' base ["repo", repo] in
  let mirage = Build.org ?app ~account:"mirage" 7175142 in
  let build (org, name, builds) = Build_unikernel.repo ?channel ~web_ui ~org ~name builds in
  Current.all @@ List.map build [
    mirage, "mirage-www", [
      unikernel "Dockerfile" ~target:"hvt" ["EXTRA_FLAGS=--tls=true --metrics --separate-networks"] ["master", "www"];
      unikernel "Dockerfile" ~target:"xen" ["EXTRA_FLAGS=--tls=true"] [];     (* (no deployments) *)
      unikernel "Dockerfile" ~target:"hvt" ["EXTRA_FLAGS=--tls=true --metrics --separate-networks"] ["next", "next"];
    ];
  ]
