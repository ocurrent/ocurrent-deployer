open Current.Syntax

module Github = Current_github

let timeout = Duration.of_min 50    (* Max build time *)

module Toxis_service = struct
  (* Docker services running on toxis. *)

  type t = {
    service : string;
    tag : string;
  }

  module Docker = Current_docker.Default

  (* Build [src/dockerfile] as a Docker service. *)
  let build ~dockerfile src =
    Docker.build (`Git src)
      ~label:dockerfile
      ~dockerfile:(Current.return (`File (Fpath.v dockerfile)))
      ~pull:true
      ~timeout

  (* Update Docker service [service] to [image].
     We also tag it, so that if someone redeploys the stack.yml then it will
     still use this version. *)
  let deploy ~tag ~service image =
    Current.all [
      Docker.tag ~tag image;
      Docker.service ~name:service ~image ()
    ]
end

module Packet_unikernel = struct
  (* Mirage unikernels running on packet.net *)

  let mirage_host_ssh = "root@147.75.204.215"

  module Docker = Current_docker.Default
  module Mirage_m1_a = Mirage.Make(Docker)

  (* Build [src/dockerfile] as an HVT unikernel. *)
  let build ~dockerfile src args =
    let build_args = List.map (fun x -> ["--build-arg"; x]) args |> List.concat in
    let dockerfile = Current.return (`File (Fpath.v dockerfile)) in
    Docker.build (`Git src)
      ~build_args
      ~dockerfile
      ~pull:true
      ~timeout

  let deploy service =
    Mirage_m1_a.deploy ~name:service ~ssh_host:mirage_host_ssh
end

(* [web_ui collapse_value] is a URL back to the deployment service, for links
   in status messages. *)
let web_ui =
  let base = Uri.of_string "https://deploy.ocamllabs.io/" in
  fun repo -> Uri.with_query' base ["repo", repo]

(* Push a Slack notification to [channel] to say that [x] is updating [service] to [commit].
   [repo] is used for the URL in the message. *)
let notify ~channel ~service ~commit ~repo x =
  let s =
    let+ state = Current.state x
    and+ commit = commit in
    let uri = Github.Api.Commit.uri commit in
    Fmt.strf "@[<h>Deploy <%a|%a> as %s: <%s|%a>@]"
      Uri.pp uri Github.Api.Commit.pp commit
      service
      (Uri.to_string (web_ui repo)) (Current_term.Output.pp Current.Unit.pp) state
  in
  Current.all [
    Current_slack.post channel ~key:("deploy-" ^ service) s;
    x   (* If [x] fails, the whole pipeline should fail too. *)
  ]

(* Build [src/dockerfile]. *)
let build ~dockerfile ~src = function
  | `Docker -> Current.ignore_value (Toxis_service.build src ~dockerfile)
  | `Unikernel flags -> Current.ignore_value (Packet_unikernel.build src ~dockerfile flags)

(* Build and deploy [src/dockerfile]. *)
let deploy ~channel ~dockerfile ~src ~commit ~collapse_value = function
  | `Docker { Toxis_service.service; tag } ->
    Toxis_service.build src ~dockerfile
    |> Toxis_service.deploy ~service ~tag
    |> notify ~channel ~service ~commit ~repo:collapse_value
  | `Unikernel (service, flags) ->
    Packet_unikernel.build src ~dockerfile flags
    |> Packet_unikernel.deploy service
    |> notify ~channel ~service ~commit ~repo:collapse_value

let docker ~service ~tag = `Docker { Toxis_service.service; tag }
let unikernel ~service args = `Unikernel (service, args)

(* This is a list of GitHub repositories to monitor.
   For each one, it lists the deployments that are made from that repository.
   For each deployment, it says which Dockerfile to build, which branch gives
   the desired live version of the service, and where to deloy it.
   For each specified branch, we will call [deploy] on that branch to build and deploy it.
   For all branches and PRs, we will call [build] to test that it could be deployed. *)
let v ~app ~notify:channel () =
  let ocurrent = Build.org ~app ~account:"ocurrent" 6853813 in
  let mirage = Build.org ~app ~account:"mirage" 7175142 in
  let repo (org, name, builds) =
    Build.repo ~web_ui ~deploy:(deploy ~channel) ~build ~org ~name builds
  in
  Current.all @@ List.map repo [
    (* OCurrent repositories *)
    ocurrent, "ocaml-ci", [
      "Dockerfile",     "live-engine", docker ~tag:"ocaml-ci-service:latest" ~service:"ocaml-ci_ci";
      "Dockerfile.web", "live-www",    docker ~tag:"ocaml-ci-web:latest"     ~service:"ocaml-ci_web";
      "Dockerfile.web", "staging-www", docker ~tag:"ocaml-ci-web:staging"    ~service:"test-www";
    ];
    ocurrent, "ocurrent-deployer", [
      "Dockerfile", "live", docker ~tag:"ci.ocamllabs.io-deployer:latest" ~service:"infra_deployer";
    ];
    ocurrent, "docker-base-images", [
      "Dockerfile", "live", docker ~tag:"base-images:latest" ~service:"base-images_builder";
    ];
    (* Mirage repositories *)
    mirage, "mirage-www", [
      "Dockerfile", "master", unikernel ~service:"www" ["TARGET=hvt"; "EXTRA_FLAGS=--tls=true"];
    ];
  ]
