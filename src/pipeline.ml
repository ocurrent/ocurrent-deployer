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

let ocaml_ci = { Github.Repo_id.owner = "ocurrent"; name = "ocaml-ci" }
let deployer = { Github.Repo_id.owner = "ocurrent"; name = "ocurrent-deployer" }
let base_images = { Github.Repo_id.owner = "ocurrent"; name = "docker-base-images " }
let mirage_www = { Github.Repo_id.owner = "mirage"; name = "mirage-www" }

let notify ~channel ~service ~commit x =
  let s =
    let+ state = Current.state x
    and+ commit = commit in
    Fmt.strf "@[<h>Deploy %a as %s: %a@]"
      Github.Api.Commit.pp commit
      service
      (Current_term.Output.pp Current.Unit.pp)
      state
  in
  Current.all [
    Current_slack.post channel ~key:("deploy-" ^ service) s;
    x   (* If [x] fails, the whole pipeline should fail too. *)
  ]

(* Build [commit], tag as [tag], and update [service] to it. *)
let deploy ~notify:channel ?(dockerfile="Dockerfile") ~tag ~service commit =
  let src = Git.fetch (Current.map Github.Api.Commit.id commit) in
  let dockerfile = Current.return (`File (Fpath.v dockerfile)) in
  let image = Docker.build ~dockerfile ~pull:true ~timeout (`Git src) in
  Current.all [
    Docker.tag ~tag image;
    Docker.service ~name:service ~image ()
  ]
  |> notify ~channel ~service ~commit

(* Build [commit] and deploy as unikernel [service]. *)
let mirage ~notify:channel ?(dockerfile="Dockerfile") ~service commit =
  let module Docker = M1_a in
  let src = Git.fetch (Current.map Github.Api.Commit.id commit) in
  let dockerfile = Current.return (`File (Fpath.v dockerfile)) in
  let image = Docker.build ~build_args:["--build-arg"; "TARGET=hvt"] ~dockerfile ~pull:true ~timeout (`Git src) in
  Mirage_m1_a.deploy mirage_config ~name:service image
  |> notify ~channel ~service ~commit

let v ~github ~notify () =
  let branch repo name = Github.Api.head_of github repo (`Ref ("refs/heads/" ^ name)) in
  let deploy = deploy ~notify in
  let mirage = mirage ~notify in
  Current.all [
    deploy (branch ocaml_ci "live-engine") ~dockerfile:"Dockerfile"     ~tag:"ocaml-ci-service:latest" ~service:"ocaml-ci_ci";
    deploy (branch ocaml_ci "live-www")    ~dockerfile:"Dockerfile.web" ~tag:"ocaml-ci-web:latest" ~service:"ocaml-ci_web";
    deploy (branch ocaml_ci "staging-www") ~dockerfile:"Dockerfile.web" ~tag:"ocaml-ci-web:staging" ~service:"test-www";
    deploy (branch deployer "live")        ~dockerfile:"Dockerfile"     ~tag:"ci.ocamllabs.io-deployer:latest" ~service:"infra_deployer";
    deploy (branch base_images "live")     ~dockerfile:"Dockerfile"     ~tag:"base-images:latest" ~service:"base-images_builder";
    (* Unikernels: *)
    mirage (branch mirage_www "live")    ~service:"mirage-www";
  ]
