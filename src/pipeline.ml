open Current.Syntax

let mirage_host_context = "m1-a"
let mirage_host_ssh = "root@147.75.33.203"

module Docker = Current_docker.Default
module M1_a = Current_docker.Make(struct let docker_context = Some mirage_host_context end)
module Git = Current_git
module Github = Current_github
module Mirage_m1_a = Mirage.Make(M1_a)

let mirage_config = Mirage_m1_a.config ~ssh_host:mirage_host_ssh ()

let timeout = Duration.of_min 50    (* Max build time *)

let web_ui =
  let base = Uri.of_string "https://deploy.ocamllabs.io/" in
  fun repo -> Uri.with_query' base ["repo", repo]

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

let docker ~dockerfile src =
  let label = Printf.sprintf "build %s" dockerfile in
  let dockerfile = Current.return (`File (Fpath.v dockerfile)) in
  Docker.build ~label ~dockerfile ~pull:true ~timeout (`Git src)

(* Build [commit] and deploy as unikernel [service]. *)
let mirage ~dockerfile src =
  let module Docker = M1_a in
  let dockerfile = Current.return (`File (Fpath.v dockerfile)) in
  Docker.build ~build_args:["--build-arg"; "TARGET=hvt"] ~dockerfile ~pull:true ~timeout (`Git src)

type docker_deployment = {
  service : string;
  tag : string;
}

let head_of ~github repo name = Github.Api.head_of github repo (`Ref ("refs/heads/" ^ name))

let repo_of_string s =
  match String.split_on_char '/' s with
  | [ owner; name ] -> { Github.Repo_id.owner; name }
  | _ -> Fmt.failwith "Invalid repo name %S (should be 'owner/name')" s

let ignore_branch items =
  items
  |> List.map (function
      | (d, _, `Docker _) -> d, `Docker
      | (d, _, `Unikernel _) -> d, `Unikernel
    )
  |> List.sort_uniq compare

let status_of_build ~repo b =
  let url = web_ui repo in
  let+ state = Current.state b in
  match state with
  | Ok _              -> Github.Api.Status.v ~url `Success ~description:"Passed"
  | Error (`Active _) -> Github.Api.Status.v ~url `Pending
  | Error (`Msg m)    -> Github.Api.Status.v ~url `Failure ~description:m

let repo ~github ~channel (repo_name, builds) =
  let root = Current.return ~label:repo_name () in
  Current.with_context root @@ fun () ->
  let repo = repo_of_string repo_name in
  let builds =
    let refs = Github.Api.ci_refs github repo in
    let collapse_value = repo_name ^ "-builds" in
    let pipeline =
      refs
      |> Current.list_iter (module Github.Api.Commit) @@ fun commit ->
      let src = Git.fetch (Current.map Github.Api.Commit.id commit) in
      Current.all (
        ignore_branch builds |> List.map (fun (dockerfile, target) ->
            match target with
            | `Docker -> Current.ignore_value (docker src ~dockerfile)
            | `Unikernel -> Current.ignore_value (mirage src ~dockerfile)
          )
      )
      |> status_of_build ~repo:collapse_value
      |> Github.Api.Commit.set_status commit "deployability"
    in
    Current.collapse
      ~key:"repo" ~value:collapse_value
      ~input:refs pipeline
  and deployments =
    Current.all (
      builds |> List.map (fun (dockerfile, branch, target) ->
          let commit = head_of ~github repo branch in
          let src = Git.fetch (Current.map Github.Api.Commit.id commit) in
          let collapse_value = Printf.sprintf "%s-%s-%s" repo_name dockerfile branch in
          let build =
            match target with
            | `Docker { service; tag } ->
              let image = docker src ~dockerfile in
              Current.all [
                Docker.tag ~tag image;
                Docker.service ~name:service ~image ()
              ]
              |> notify ~channel ~service ~commit ~repo:collapse_value
            | `Unikernel service ->
              mirage src ~dockerfile
              |> Mirage_m1_a.deploy mirage_config ~name:service
              |> notify ~channel ~service ~commit ~repo:collapse_value
          in
          Current.collapse
            ~key:"repo" ~value:collapse_value
            ~input:commit build
        )
    )
  in
  Current.all [builds; deployments]

let docker ~service ~tag = `Docker { service; tag }
let unikernel ~service = `Unikernel service

(* This is a list of GitHub repositories to monitor.
   For each one, it lists the Dockerfiles in it from which binaries can be built.
   For each binary, it says which branch gives the desired live version of the service,
   and where to deloy it. *)
let v ~github ~notify:channel () =
  Current.all @@ List.map (repo ~github ~channel) [
    (* Docker services *)
    "ocurrent/ocaml-ci", [
      "Dockerfile",     "live-engine", docker ~tag:"ocaml-ci-service:latest" ~service:"ocaml-ci_ci";
      "Dockerfile.web", "live-www",    docker ~tag:"ocaml-ci-web:latest"     ~service:"ocaml-ci_web";
      "Dockerfile.web", "staging-www", docker ~tag:"ocaml-ci-web:staging"    ~service:"test-www";
    ];
    "ocurrent/ocurrent-deployer", [
      "Dockerfile", "live", docker ~tag:"ci.ocamllabs.io-deployer:latest" ~service:"infra_deployer";
    ];
    "ocurrent/docker-base-images", [
      "Dockerfile", "live", docker ~tag:"base-images:latest" ~service:"base-images_builder";
    ];
    (* Unikernels *)
    "mirage/mirage-www", [
      "Dockerfile", "live", unikernel ~service:"mirage-www";
    ];
  ]
