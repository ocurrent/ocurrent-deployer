(* Different Deployer pipelines available. *)
module Flavour = struct
  type t = [`Tarides | `OCaml | `Mirage]
  let cmdliner =
    let open Cmdliner in
    let flavours = ["tarides", `Tarides
                   ; "ocaml", `OCaml
                   ; "mirage", `Mirage
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

let docker ~sched { dockerfile; targets; archs; options } =
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
  ]

  (* This is a list of GitHub repositories to monitor.
    For each one, it lists the builds that are made from that repository.
    For each build, it says which which branch gives the desired live version of
    the service, and where to deploy it. *)
  let services ?app () =
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
              [`Ci3 "deployer_deployer"];
          ]
      ];
      ocurrent, "ocaml-ci", [
        make_docker
          "Dockerfile"
          [
            make_deployment
              ~branch:"live-engine"
              ~target:"ocurrent/ocaml-ci-service:live"
              [`Ci "ocaml-ci_ci"];
          ]
          ~archs:[`Linux_x86_64; `Linux_arm64];
        make_docker
          "Dockerfile.gitlab"
          [
            make_deployment
              ~branch:"live-engine"
              ~target:"ocurrent/ocaml-ci-gitlab-service:live"
              [`Ci "ocaml-ci_gitlab"];
          ]
          ~archs:[`Linux_x86_64; `Linux_arm64];
        make_docker
          "Dockerfile.web"
          [
            make_deployment
              ~branch:"live-www"
              ~target:"ocurrent/ocaml-ci-web:live"
              [`Ci "ocaml-ci_web"];
            make_deployment
              ~branch:"staging-www"
              ~target:"ocurrent/ocaml-ci-web:staging"
              [`Ci "test-www"];
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
      ocurrent, "opam-repo-ci", [
        make_docker
          "Dockerfile"
          [
            make_deployment
              ~branch:"live"
              ~target:"ocurrent/opam-repo-ci:live"
              [`Opamrepo "opam-repo-ci_opam-repo-ci"];
          ]
          ~archs:[`Linux_x86_64; `Linux_arm64];
        make_docker
          "Dockerfile.web"
          [
            make_deployment
              ~branch:"live-web"
              ~target:"ocurrent/opam-repo-ci-web:live"
              [`Opamrepo "opam-repo-ci_opam-repo-ci-web"];
          ]
          ~archs:[`Linux_x86_64; `Linux_arm64];
      ];
      ocurrent, "opam-health-check", [
        make_docker
          "Dockerfile"
          [
            make_deployment
              ~branch:"live"
              ~target:"ocurrent/opam-health-check:live"
              [`Check "infra_opam-health-check"; `Check "infra_opam-health-check-freebsd"];
          ];
      ];
      ocurrent, "ocaml-multicore-ci", [
        make_docker
          "Dockerfile"
          [
            make_deployment
              ~branch:"live"
              ~target:"ocurrent/multicore-ci:live"
              [`Ci4 "infra_multicore-ci"];
          ];
        make_docker
          "Dockerfile.web"
          [
            make_deployment
              ~branch:"live-web"
              ~target:"ocurrent/multicore-ci-web:live"
              [`Ci4 "infra_multicore-ci-web"];
          ];
      ];
      ocurrent, "ocurrent.org", [
        make_docker
          "Dockerfile"
          [
            make_deployment
              ~branch:"live-engine"
              ~target:"ocurrent/ocurrent.org:live-engine"
              [`Ci3 "ocurrent_org_watcher"];
          ];
      ];
      ocaml_bench, "sandmark-nightly", [
        make_docker
          "Dockerfile"
          [
            make_deployment
              ~branch:"main"
              ~target:"ocurrent/sandmark-nightly:live"
              [`Ci3 "sandmark_sandmark"];
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
              [`Ci4 "infra_multicoretests-ci"];
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

  let docker ~sched ~staging_auth t =
    let timeout =
      if List.mem `Linux_riscv64 t.archs then Int64.mul Build.timeout 2L
      else Build.timeout
    in
    let sched = Current_ocluster.v ~timeout ?push_auth:staging_auth sched in
    docker ~sched t

  let v ?app ?notify:channel ?filter ~sched ~staging_auth () =
    (* [web_ui collapse_value] is a URL back to the deployment service, for links
      in status messages. *)
    let web_ui repo = Uri.with_query' base_url ["repo", repo] in
    let build (org, name, builds) =
      Cluster_build.repo ?channel ~web_ui ~org ~name builds
    in
    let docker = docker ~sched ~staging_auth in
    services ?app ()
    |> List.map (fun (org, name, deployments) ->
      let deployments = List.map docker deployments in
      (org, name, deployments))
    |> filter_list filter
    |> List.map build
    |> Current.all
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
  ]

  (* This is a list of GitHub repositories to monitor.
    For each one, it lists the builds that are made from that repository.
    For each build, it says which which branch gives the desired live version of
    the service, and where to deploy it. *)
  let services ?app () =
    (* GitHub organisations to monitor. *)
    let ocurrent = Build.org ?app ~account:"ocurrent" 23342906 in
    let ocaml = Build.org ?app ~account:"ocaml" 23711648 in
    [
      ocurrent, "ocurrent-deployer", [
        make_docker
          "Dockerfile"
          [
            make_deployment
              ~branch:"live-ocaml-org"
              ~target:"ocurrent/ci.ocamllabs.io-deployer:live-ocaml-org"
              [`Ocamlorg_deployer "infra_deployer"];
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
              [`OCamlorg_v3b "infra_www"]
          ]
          ~options:include_git;
        (* Staging branch for ocaml.org website. *)
        make_docker
          "Dockerfile"
          [
            make_deployment
              ~branch:"staging"
              ~target:"ocurrent/v3.ocaml.org-server:staging"
              [`OCamlorg_v3c "infra_www"]
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
              [`Ocamlorg_images "base-images_builder"];
          ];
      ];
      ocurrent, "ocaml-docs-ci", [
        make_docker
          "Dockerfile"
          [
            make_deployment
              ~branch:"live"
              ~target:"ocurrent/docs-ci:live"
              [`Docs "infra_docs-ci"];
          ];
        make_docker
          "docker/init/Dockerfile"
          [
            make_deployment
              ~branch:"live"
              ~target:"ocurrent/docs-ci-init:live"
              [`Docs "infra_init"];
          ];
        make_docker
          "docker/storage/Dockerfile"
          [
            make_deployment
              ~branch:"live"
              ~target:"ocurrent/docs-ci-storage-server:live"
              [`Docs "infra_storage-server"];
          ];
        make_docker
          "Dockerfile"
          [
            make_deployment
              ~branch:"staging"
              ~target:"ocurrent/docs-ci:staging"
              [`Staging_docs "infra_docs-ci"];
          ];
        make_docker
          "docker/init/Dockerfile"
          [
            make_deployment
              ~branch:"staging"
              ~target:"ocurrent/docs-ci-init:staging"
              [`Staging_docs "infra_init"];
          ];
        make_docker
          "docker/storage/Dockerfile"
          [
            make_deployment
              ~branch:"staging"
              ~target:"ocurrent/docs-ci-storage-server:staging"
              [`Staging_docs "infra_storage-server"];
          ];
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

  let extras () =
    let tarsnap =
      let monthly = Current_cache.Schedule.v ~valid_for:(Duration.of_day 30) () in
      Current_ssh.run ~schedule:monthly "watch.ocaml.org" ~key:"tarsnap" (Current.return ["./tarsnap-backup.sh"])
    in
    let peertube =
      let weekly = Current_cache.Schedule.v ~valid_for:(Duration.of_day 7) () in
      let image = Cluster.Watch_docker.pull ~schedule:weekly "chocobozzz/peertube:production-bookworm" in
      Cluster.Watch_docker.service ~name:"infra_peertube" ~image ()
    in
    [tarsnap; peertube]

  let v ?app ?notify:channel ?filter ~sched ~staging_auth () =
    (* [web_ui collapse_value] is a URL back to the deployment service, for links
      in status messages. *)
    let web_ui repo = Uri.with_query' base_url ["repo", repo] in
    let build (org, name, builds) =
      Cluster_build.repo ?channel ~web_ui ~org ~name builds
    in
    let build_for_registry ?additional_build_args (org, name, builds) =
      Build_registry.repo ?channel ?additional_build_args ~web_ui ~org ~name builds
    in
    let sched = Current_ocluster.v ~timeout:Build.timeout ?push_auth:staging_auth sched in
    let docker = docker ~sched in
    let pipelines =
      services ?app ()
      |> List.map (fun (org, name, deployments) ->
        let deployments = List.map docker deployments in
        (org, name, deployments))
      |> filter_list filter
      |> List.map build
    in
    let opam_repository_pipelines, additional_build_args =
      let pipelines, args = opam_repository ?app () in
      let filtered_pipelines = filter_list filter @@ pipelines in
      filtered_pipelines, args
    in
    Current.all (
      (List.map (build_for_registry ~additional_build_args) opam_repository_pipelines)
      @ pipelines
      @ extras ())
end

module Mirage = struct
  let base_url = Uri.of_string "https://deploy.mirage.io/"

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

  let docker_services ?app () =
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
              [`Cimirage "infra_mirage-ci"]
          ]
          ~options:(include_git |> build_kit)
      ];
      ocurrent, "ocurrent-deployer", [
        make_docker
          "Dockerfile"
          [
            make_deployment
              ~branch:"live-mirage"
              ~target:"ocurrent/deploy.mirage.io:live"
              [`Cimirage "infra_deployer"]
          ];
      ];
      ocurrent, "caddy-rfc2136", [
        make_docker
          "Dockerfile"
          [
            make_deployment
              ~branch:"master"
              ~target:"ocurrent/caddy-rfc2136:live"
              [`Cimirage "infra_caddy"]
          ];
      ];
    ]

  let v ?app ?notify:channel ~sched ~staging_auth () =
    (* [web_ui collapse_value] is a URL back to the deployment service, for links
      in status messages. *)
    let web_ui repo = Uri.with_query' base_url ["repo", repo] in
    let build_unikernel (org, name, builds) = Build_unikernel.repo ?channel ~web_ui ~org ~name builds in
    let build_docker (org, name, builds) = Cluster_build.repo ?channel ~web_ui ~org ~name builds in
    let sched = Current_ocluster.v ~timeout:Build.timeout ?push_auth:staging_auth sched in
    let docker = docker ~sched in
    let docker_services =
      docker_services ?app ()
      |> List.map (fun (org, name, deployments) ->
        let deployments = List.map docker deployments in
        (org, name, deployments))
      |> List.map build_docker
    in
    Current.all @@
      ((List.map build_unikernel @@ unikernel_services ?app ())
      @ docker_services)
end
