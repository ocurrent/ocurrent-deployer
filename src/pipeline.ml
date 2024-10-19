open Current.Syntax

module Github = Current_github

(* A docker module parameterized by the docker context indicating the machine a service is a run on *)
let docker_context context : (module Current_docker.S.DOCKER) =
  (module Current_docker.Make(struct let docker_context = (Some context) end))

(* The default docker module indicates the machine that the deployer service itself is run on *)
let default_docker_context : (module Current_docker.S.DOCKER) =
  (module Current_docker.Default)

let or_fail = function
  | Ok x -> x
  | Error (`Msg m) -> failwith m

module Build_unikernel = Build.Make(Packet_unikernel)
module Build_registry = Build.Make(Docker_registry)
module Cluster_build = Build.Make(Cluster)

type deployment = {
  branch : string;
  target : string; (* The docker tag of the image that the branch is built to *)
  services : Cluster.service list;
}

let make_deployment ~branch ~target services = { branch; target; services; }

type docker = {
  dockerfile : string;
  targets : deployment list;
  archs : Cluster.Arch.t list;
  options : Cluster_api.Docker.Spec.options;
}

let make_docker ?(archs=[`Linux_x86_64]) ?(options=Cluster_api.Docker.Spec.defaults) dockerfile targets =
  { dockerfile; targets; archs; options }

type service = Build.org * string * docker list

type pipeline =
  ?app:Current_github.App.t ->
  ?notify:Current_slack.channel ->
  ?filter:(Current_github.Repo_id.t -> bool) ->
  sched:Current_ocluster.Connection.t ->
  staging_auth:(string * string) option ->
  unit ->
  unit Current.t

type deployer =
  { pipeline: pipeline
  ; admins: string list
  }

module type Deployer = sig
  (** The interface for a pipelines that deploys a set of services *)

  val base_url : Uri.t

  val services : ?app:Current_github.App.t -> unit -> service list
end

let docker ~sched ~push_auth { dockerfile; targets; archs; options } =
  let timeout =
    if List.mem `Linux_riscv64 archs then
      (* The risc machines are very slow, so we need to increase the timeout *)
      Int64.mul Build.timeout 2L
    else
      Build.timeout
  in
  let sched = Current_ocluster.v ~timeout ?push_auth sched in
  let build_info = { Cluster.sched; dockerfile = `Path dockerfile; options; archs } in
  let deploys =
    targets
    |> List.map (fun { branch; target; services } ->
        branch, { Cluster.
                  hub_id = Cluster_api.Docker.Image_id.of_string target |> or_fail;
                  services
                }
      )
  in
  (build_info, deploys)

let docker_registry timeout dockerfile targets =
  let build_info = { Docker_registry.dockerfile; timeout } in
  let deploys = List.map (fun (branch, tag, services) -> branch, { Docker_registry.tag; services }) targets in
  (build_info, deploys)

let filter_list filter items =
  match filter with
  | None -> items
  | Some filter ->
    items |> List.filter @@ fun (org, name, _) ->
    filter { Current_github.Repo_id.owner = Build.account org; name }

let include_git = { Cluster_api.Docker.Spec.defaults with include_git = true }

let build_kit (v : Cluster_api.Docker.Spec.options) = { v with buildkit = true }

module Tarides = struct
  let base_url = Uri.of_string "https://deploy.ci.dev/"

  let admins = [
    "github:avsm";
    "github:dra27";
    "github:moyodiallo";
    "github:MisterDA";
    "github:mtelvers";
    "github:punchagan";
    "github:samoht";
    "github:shonfeder";
    "github:talex5";
    "github:tmcgilchrist";
    "github:cuihtlauac";
  ]

  (* The docker context for the services *)
  let ocaml_ci_dev = docker_context "ocaml.ci.dev"
  let ci4_ocamllabs_io = docker_context "ci4.ocamllabs.io"
  let ci3_ocamllabs_io = docker_context "ci3.ocamllabs.io"

  (* This is a list of GitHub repositories to monitor.
    For each one, it lists the builds that are made from that repository.
    For each build, it says which which branch gives the desired live version of
    the service, and where to deploy it. *)
  let services ?app () : service list =
    (* GitHub organisations to monitor. *)
    let ocurrent = Build.org ?app ~account:"ocurrent" 12497518 in
    let ocaml_bench = Build.org ?app ~account:"ocaml-bench" 19839896 in
    [
      ocurrent, "ocurrent-deployer", [
        make_docker
          "Dockerfile"
          [
            make_deployment
              ~branch:"live-ci3"
              ~target:"ocurrent/ci.ocamllabs.io-deployer:live-ci3"
              [{name = "deployer_deployer"; docker_context = default_docker_context; uri = Some "deploy.ci.dev"}];
          ]
      ];
      ocurrent, "ocaml-ci", [
        make_docker
          "Dockerfile"
          [
            make_deployment
              ~branch:"live-engine"
              ~target:"ocurrent/ocaml-ci-service:live"
              [{name = "ocaml-ci_ci"; docker_context = ocaml_ci_dev; uri = Some "ocaml.ci.dev:8100"}];
          ]
          ~archs:[`Linux_x86_64; `Linux_arm64];
        make_docker
          "Dockerfile.gitlab"
          [
            make_deployment
              ~branch:"live-engine"
              ~target:"ocurrent/ocaml-ci-gitlab-service:live"
              [{name = "ocaml-ci_gitlab"; docker_context = ocaml_ci_dev; uri = Some "ocaml.ci.dev:8200"}];
          ]
          ~archs:[`Linux_x86_64; `Linux_arm64];
        make_docker
          "Dockerfile.web"
          [
            make_deployment
              ~branch:"live-www"
              ~target:"ocurrent/ocaml-ci-web:live"
              [{name = "ocaml-ci_web"; docker_context = ocaml_ci_dev; uri = Some "ocaml.ci.dev"}];
            make_deployment
              ~branch:"staging-www"
              ~target:"ocurrent/ocaml-ci-web:staging"
              [{name = "test-www"; docker_context = ocaml_ci_dev; uri = None}];
          ]
          ~archs:[`Linux_x86_64; `Linux_arm64];
      ];
      ocurrent, "ocluster", [
        make_docker
          "Dockerfile"
          [
            make_deployment
              ~branch:"live-scheduler"
              ~target:"ocurrent/ocluster-scheduler:live"
              [];
          ]
          ~archs:[`Linux_x86_64; `Linux_arm64]
          ~options:include_git;
        make_docker
          "Dockerfile.worker"
          [
            make_deployment
              ~branch:"live-worker"
              ~target:"ocurrent/ocluster-worker:live"
              [];
          ]
          ~archs:[`Linux_x86_64; `Linux_arm64; `Linux_ppc64; `Linux_s390x; `Linux_riscv64]
          ~options:(include_git |> fun v ->  { v with build_args =  ["--ulimit stack=1000000000:1000000000"]});
        make_docker
          "Dockerfile.worker.alpine"
          [
            make_deployment
              ~branch:"live-worker"
              ~target:"ocurrent/ocluster-worker:alpine"
              [];
          ]
          ~archs:[`Linux_x86_64; `Linux_arm64] ~options:include_git;
      ];
      ocurrent, "clarke", [
        make_docker
          "Dockerfile"
          [
            make_deployment
              ~branch:"live"
              ~target:"ocurrent/clarke:live"
              [];
          ]
          ~archs:[`Linux_x86_64; `Linux_arm64] ~options:include_git;
      ];
      ocurrent, "ocaml-multicore-ci", [
        make_docker
          "Dockerfile"
          [
            make_deployment
              ~branch:"live"
              ~target:"ocurrent/multicore-ci:live"
              [{name = "infra_multicore-ci"; docker_context = ci4_ocamllabs_io; uri = Some "ocaml-multicore.ci.dev:8100"}];
          ];
        make_docker
          "Dockerfile.web"
          [
            make_deployment
              ~branch:"live-web"
              ~target:"ocurrent/multicore-ci-web:live"
              [{name = "infra_multicore-ci-web"; docker_context = ci4_ocamllabs_io; uri = Some "ocaml-multicore.ci.dev"}];
          ];
      ];
      ocurrent, "ocurrent.org", [
        make_docker
          "Dockerfile"
          [
            make_deployment
              ~branch:"live-engine"
              ~target:"ocurrent/ocurrent.org:live-engine"
              [{name = "ocurrent_org_watcher"; docker_context = ci3_ocamllabs_io; uri = Some "watcher.ci.dev"}];
          ];
      ];
      ocaml_bench, "sandmark-nightly", [
        make_docker
          "Dockerfile"
          [
            make_deployment
              ~branch:"main"
              ~target:"ocurrent/sandmark-nightly:live"
              [{name = "sandmark_sandmark"; docker_context = ci3_ocamllabs_io; uri = Some "sandmark.tarides.com"}];
          ]
          ~options:include_git;
      ];
      ocurrent, "solver-service", [
        make_docker
          "Dockerfile"
          [
            make_deployment
              ~branch:"live"
              ~target:"ocurrent/solver-service:live"
              [];
          ]
          ~archs:[`Linux_x86_64; `Linux_arm64] ~options:include_git;
        make_docker
          "Dockerfile"
          [
            make_deployment
              ~branch:"staging"
              ~target:"ocurrent/solver-service:staging"
              [];
          ]
          ~archs:[`Linux_x86_64; `Linux_arm64] ~options:include_git;
      ];
      ocurrent, "multicoretests-ci", [
        make_docker
          "Dockerfile"
          [
            make_deployment
              ~branch:"live"
              ~target:"ocurrent/multicoretests-ci:live"
              [{name = "infra_multicoretests-ci"; docker_context = ci4_ocamllabs_io; uri = Some "ocaml-multicoretests.ci.dev:8100" }];
          ];
      ];
      ocurrent, "ocurrent-observer", [
        make_docker
          "Dockerfile"
          [
            make_deployment
              ~branch:"live"
              ~target:"ocurrent/ocurrent-observer:live"
              [];
          ]
          ~archs:[`Linux_riscv64] ~options:include_git;
      ];
      ocurrent, "ocurrent-configurator", [
        make_docker
          "Dockerfile"
          [
            make_deployment
              ~branch:"live"
              ~target:"ocurrent/ocurrent-configurator:live"
              [];
          ]
          ~archs:[`Linux_riscv64] ~options:include_git;
      ];
    ]

  let v ?app ?notify:channel ?filter ~sched ~staging_auth () =
    (* [web_ui collapse_value] is a URL back to the deployment service, for links
      in status messages. *)
    let web_ui repo = Uri.with_query' base_url ["repo", repo] in
    let build (org, name, builds) =
      Cluster_build.repo ?channel ~web_ui ~org ~name builds
    in
    services ?app ()
    |> List.map (fun (org, name, deployments) ->
      let deployments = List.map (docker ~sched ~push_auth:staging_auth) deployments in
      (org, name, deployments))
    |> filter_list filter
    |> List.map build
    |> Current.all

  let deployer = {pipeline = v; admins}
end

module Ocaml_org = struct
  let base_url = Uri.of_string "https://deploy.ci.ocaml.org"

  let admins = [
    "github:AltGr";
    "github:avsm";
    "github:dra27";
    "github:moyodiallo";
    "github:mtelvers";
    "github:punchagan";
    "github:rjbou";
    "github:samoht";
    "github:shonfeder";
    "github:talex5";
    "github:tmcgilchrist";
    "github:cuihtlauac";
  ]

  (* The docker context for the services *)
  let v3b_ocaml_org = docker_context "v3b.ocaml.org"
  let v3c_ocaml_org = docker_context "v3c.ocaml.org"
  let docs_ci_ocaml_org = docker_context "docs.ci.ocaml.org"
  let staging_docs_ci_ocaml_org = docker_context "staging.docs.ci.ocaml.org"
  let opam_ci_ocaml_org = docker_context "opam.ci.ocaml.org"
  let check_ci_ocaml_org = docker_context "check.ci.ocaml.org"
  let get_dune_build = docker_context "get.dune.build"
  let ci3_ocamllabs_io = docker_context "ci3.ocamllabs.io"

  (* This is a list of GitHub repositories to monitor.
    For each one, it lists the builds that are made from that repository.
    For each build, it says which which branch gives the desired live version of
    the service, and where to deploy it. *)
  let services ?app () : service list =
    (* GitHub organisations to monitor. *)
    let ocurrent = Build.org ?app ~account:"ocurrent" 23342906 in
    let ocaml = Build.org ?app ~account:"ocaml" 23711648 in
    let ocaml_dune = Build.org ?app ~account:"ocaml-dune" 55475870 in
    [
      ocurrent, "ocurrent-deployer", [
        make_docker
          "Dockerfile"
          [
            make_deployment
              ~branch:"live-ocaml-org"
              ~target:"ocurrent/ci.ocamllabs.io-deployer:live-ocaml-org"
              [{name = "infra_deployer"; docker_context = default_docker_context; uri = Some "deploy.ci.ocaml.org"}];
          ];
      ];
      ocaml, "ocaml.org", [
        (* New V3 ocaml.org website. *)
        make_docker
          "Dockerfile"
          [
            make_deployment
              ~branch:"main"
              ~target:"ocurrent/v3.ocaml.org-server:live"
              [{name = "infra_www"; docker_context = v3b_ocaml_org; uri = Some "ocaml.org"}]
          ]
          ~options:include_git;
        (* Staging branch for ocaml.org website. *)
        make_docker
          "Dockerfile"
          [
            make_deployment
              ~branch:"staging"
              ~target:"ocurrent/v3.ocaml.org-server:staging"
              [{name = "infra_www"; docker_context = v3c_ocaml_org; uri = Some "staging.ocaml.org"}]
          ]
          ~options:include_git
      ];
      ocurrent, "docker-base-images", [
        (* Docker base images @ images.ci.ocaml.org *)
        make_docker
          "Dockerfile"
          [
            make_deployment
              ~branch:"live"
              ~target:"ocurrent/base-images:live"
              [{name = "base-images_builder"; docker_context = ci3_ocamllabs_io; uri = Some "images.ci.ocaml.org"}];
          ];
      ];
      ocurrent, "ocaml-docs-ci", [
        make_docker
          "Dockerfile"
          [
            make_deployment
              ~branch:"live"
              ~target:"ocurrent/docs-ci:live"
              [{name = "infra_docs-ci"; docker_context = docs_ci_ocaml_org; uri = Some "docs.ci.ocaml.org"}];
          ];
        make_docker
          "docker/init/Dockerfile"
          [
            make_deployment
              ~branch:"live"
              ~target:"ocurrent/docs-ci-init:live"
              [{name = "infra_init"; docker_context = docs_ci_ocaml_org; uri = None }];
          ];
        make_docker
          "docker/storage/Dockerfile"
          [
            make_deployment
              ~branch:"live"
              ~target:"ocurrent/docs-ci-storage-server:live"
              [{name = "infra_storage-server"; docker_context = docs_ci_ocaml_org; uri = None }];
          ];
        make_docker
          "Dockerfile"
          [
            make_deployment
              ~branch:"staging"
              ~target:"ocurrent/docs-ci:staging"
              [{name = "infra_docs-ci"; docker_context = staging_docs_ci_ocaml_org; uri = Some "staging.docs.ci.ocamllabs.io"}];
          ];
        make_docker
          "docker/init/Dockerfile"
          [
            make_deployment
              ~branch:"staging"
              ~target:"ocurrent/docs-ci-init:staging"
              [{name = "infra_init"; docker_context = staging_docs_ci_ocaml_org; uri = None}];
          ];
        make_docker
          "docker/storage/Dockerfile"
          [
            make_deployment
              ~branch:"staging"
              ~target:"ocurrent/docs-ci-storage-server:staging"
              [{name = "infra_storage-server"; docker_context = staging_docs_ci_ocaml_org; uri = None}];
          ];
      ];
      ocurrent, "opam-health-check", [
        make_docker
          "Dockerfile"
          [
            make_deployment
              ~branch:"live"
              ~target:"ocurrent/opam-health-check:live"
              [ {name = "infra_opam-health-check"; docker_context = check_ci_ocaml_org; uri = Some "check.ci.ocaml.org"}
              ; {name = "infra_opam-health-check-windows"; docker_context = check_ci_ocaml_org; uri = Some "windows.check.ci.dev"}
              ; {name = "infra_opam-health-check-freebsd"; docker_context = check_ci_ocaml_org; uri = Some "freebsd.check.ci.dev"}];
          ];
      ];
      ocurrent, "opam-repo-ci", [
        make_docker
          "Dockerfile"
          [
            make_deployment
              ~branch:"live"
              ~target:"ocurrent/opam-repo-ci:live"
              [{name = "opam-repo-ci_opam-repo-ci"; docker_context = opam_ci_ocaml_org; uri = Some "opam-repo.ci.ocaml.org" }];
          ]
          ~archs:[`Linux_x86_64; `Linux_arm64];
        make_docker
          "Dockerfile.web"
          [
            make_deployment
              ~branch:"live-web"
              ~target:"ocurrent/opam-repo-ci-web:live"
              [{name = "opam-repo-ci_opam-repo-ci-web"; docker_context = opam_ci_ocaml_org; uri = Some "opam.ci.ocaml.org" }];
          ]
          ~archs:[`Linux_x86_64; `Linux_arm64];
      ];
      ocaml_dune, "binary-distribution", [
        make_docker
          "Dockerfile"
          [
            make_deployment
              ~branch:"main"
              ~target:"ocurrent/dune-binary-distribution:live"
              [{name = "infra_www"; docker_context = get_dune_build; uri = Some "get.dune.build"}]
          ]
      ];
    ]

  let opam_repository ?app () =
    (* GitHub organisations to monitor. *)
    let ocaml_opam = Build.org ?app ~account:"ocaml-opam" 23690708 in
    let pipelines =
      [
        ocaml_opam, "opam2web", [
          docker_registry (Duration.of_min 360) "Dockerfile"
            ["live", "opam.ocaml.org:live", [`Ocamlorg_opam4 "infra_opam_live"; `Ocamlorg_opam5 "infra_opam_live"];
              "live-staging", "opam.ocaml.org:staging", [`Ocamlorg_opam4 "infra_opam_staging"; `Ocamlorg_opam5 "infra_opam_staging"]]
        ];
      ]
    in
    let head_of repo id =
      match Build.api ocaml_opam with
      | Some api ->
        let id_type = match id with
        | `Ref x -> `Ref x
        | `PR pri -> `PR pri.Github.Api.Ref.id
        in
        Current.map Github.Api.Commit.id @@ Github.Api.head_of api repo id_type
      | None -> Github.Api.Anonymous.head_of repo id
    in
    let additional_build_args =
      let+ opam_repository_commit =
        head_of { Github.Repo_id.owner = "ocaml"; name = "opam-repository" } @@ `Ref "refs/heads/master"
      and+ platform_blog_commit =
        head_of { Github.Repo_id.owner = "ocaml"; name = "platform-blog" } @@ `Ref "refs/heads/master"
      and+ opam_commit =
        head_of { Github.Repo_id.owner = "ocaml"; name = "opam" } @@ `Ref "refs/heads/master"
      in
      [
        "OPAM_REPO_GIT_SHA=" ^ Current_git.Commit_id.hash opam_repository_commit;
        "BLOG_GIT_SHA=" ^ Current_git.Commit_id.hash platform_blog_commit;
        "OPAM_GIT_SHA=" ^ Current_git.Commit_id.hash opam_commit
      ]
    in
    pipelines, additional_build_args

  let watch_ocaml_org = "watch.ocaml.org"
  module Watch_docker = (val docker_context watch_ocaml_org)

  let v ?app ?notify:channel ?filter ~sched ~staging_auth () =
    (* [web_ui collapse_value] is a URL back to the deployment service, for links
      in status messages. *)
    let web_ui repo = Uri.with_query' base_url ["repo", repo] in
    let docker_registry_pipelines =
      let pipelines, args = opam_repository ?app () in
      pipelines
      |> filter_list filter
      |> List.map (fun (org, name, builds) ->
          Build_registry.repo ?channel ~additional_build_args:args ~web_ui ~org ~name builds)
    in
    let services_pipelines =
      services ?app ()
      |> List.map (fun (org, name, deployments) ->
        let deployments = List.map (docker ~sched ~push_auth:staging_auth) deployments in
        (org, name, deployments))
      |> filter_list filter
      |> List.map (fun (org, name, builds) ->
          Cluster_build.repo ?channel ~web_ui ~org ~name builds)
    in
    let tarsnap =
      let monthly = Current_cache.Schedule.v ~valid_for:(Duration.of_day 30) () in
      Current_ssh.run ~schedule:monthly watch_ocaml_org ~key:"tarsnap" (Current.return ["./tarsnap-backup.sh"])
    in
    let peertube =
      let weekly = Current_cache.Schedule.v ~valid_for:(Duration.of_day 7) () in
      let image = Watch_docker.pull ~schedule:weekly "chocobozzz/peertube:production-bookworm" in
      Watch_docker.service ~name:"infra_peertube" ~image ()
    in
    Current.all (
      docker_registry_pipelines
      @ services_pipelines
      @ [tarsnap; peertube])

  let deployer = {pipeline = v; admins}
end

module Mirage = struct
  let base_url = Uri.of_string "https://deploy.mirageos.org/"

  let admins = [
    "github:avsm";
    "github:dra27";
    "github:hannesm";
    "github:moyodiallo";
    "github:mtelvers";
    "github:punchagan";
    "github:samoht";
    "github:shonfeder";
    "github:talex5";
    "github:tmcgilchrist";
    "github:cuihtlauac";
  ]

  let unikernel dockerfile ~target args services =
    let build_info = { Packet_unikernel.dockerfile; target; args } in
    let deploys =
      services
      |> List.map (fun (branch, service) -> branch, { Packet_unikernel.service }) in
    (build_info, deploys)

  let unikernel_services ?app () =
    (* GitHub organisations to monitor. *)
    let mirage = Build.org ?app ~account:"mirage" 7175142 in
    [
      mirage, "mirage-www", [
        unikernel "Dockerfile" ~target:"hvt" ["EXTRA_FLAGS=--tls=true --metrics --separate-networks"] ["master", "www"];
        unikernel "Dockerfile" ~target:"xen" ["EXTRA_FLAGS=--tls=true"] [];     (* (no deployments) *)
        unikernel "Dockerfile" ~target:"hvt" ["EXTRA_FLAGS=--tls=true --metrics --separate-networks"] ["next", "next"];
      ];
    ]

  (* The docker context for the services *)
  let ci_mirage_org = docker_context "ci.mirageos.org"

  let services ?app () : service list =
    (* GitHub organisations to monitor. *)
    let ocurrent = Build.org ?app ~account:"ocurrent" 6853813 in
    [
      ocurrent, "mirage-ci", [
        make_docker
          "Dockerfile"
          [
            make_deployment
              ~branch:"live"
              ~target:"ocurrent/mirage-ci:live"
              [{name = "infra_mirage-ci"; docker_context = ci_mirage_org; uri = Some "ci.mirageos.org" }]
          ]
          ~options:(include_git |> build_kit)
      ];
      ocurrent, "ocurrent-deployer", [
        make_docker
          "Dockerfile"
          [
            make_deployment
              ~branch:"live-mirage"
              ~target:"ocurrent/deploy.mirageos.org:live"
              [{name = "infra_deployer"; docker_context = ci_mirage_org; uri = Some "deploy.mirageos.org" }]
          ];
      ];
      ocurrent, "caddy-rfc2136", [
        make_docker
          "Dockerfile"
          [
            make_deployment
              ~branch:"master"
              ~target:"ocurrent/caddy-rfc2136:live"
              [{name = "infra_caddy"; docker_context = ci_mirage_org; uri = None }]
          ];
      ];
    ]

  let v ?app ?notify:channel ?filter:_ ~sched ~staging_auth () =
    (* [web_ui collapse_value] is a URL back to the deployment service, for links
      in status messages. *)
    let web_ui repo = Uri.with_query' base_url ["repo", repo] in
    let build_unikernel (org, name, builds) = Build_unikernel.repo ?channel ~web_ui ~org ~name builds in
    let build_docker (org, name, builds) = Cluster_build.repo ?channel ~web_ui ~org ~name builds in
    let docker_services =
      services ?app ()
      |> List.map (fun (org, name, deployments) ->
        let deployments = List.map (docker ~sched ~push_auth:staging_auth) deployments in
        (org, name, deployments))
      |> List.map build_docker
    in
    Current.all @@
      ((List.map build_unikernel @@ unikernel_services ?app ())
      @ docker_services)

  let deployer = {pipeline = v; admins}
end

(* cmdliner term to select the deployer to run *)
let cmdliner =
  let flavours =
    [ "tarides", `Tarides
    ; "ocaml", `OCaml
    ; "mirage", `Mirage
    ]
  in
  let pipeline_data = function
    | `Tarides -> Tarides.deployer
    | `OCaml -> Ocaml_org.deployer
    | `Mirage -> Mirage.deployer
  in
  let open Cmdliner in
  let enum_alts = Arg.doc_alts_enum flavours in
  let doc = Format.asprintf "Pipeline flavour to run. $(docv) must be %s." enum_alts in
  let flavour =
    Arg.(required
         & opt (some & enum flavours) None
         & info ["flavour"] ~doc ~docv:"FLAVOUR")
  in
  Term.(const pipeline_data $ flavour)
