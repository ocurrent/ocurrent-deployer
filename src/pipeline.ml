module Github = Current_github

let timeout = Duration.of_min 50    (* Max build time *)

module Toxis_service = struct
  (* Docker services running on toxis. *)

  module Docker = Current_docker.Default

  type build_info = {
    dockerfile : string;
  }

  type binary = Docker.Image.t

  type deploy_info = {
    service : string;
    tag : string;
  }

  (* Build [src/dockerfile] as a Docker service. *)
  let build { dockerfile } src =
    Docker.build (`Git src)
      ~label:dockerfile
      ~dockerfile:(Current.return (`File (Fpath.v dockerfile)))
      ~pull:true
      ~timeout

  let name info = info.service

  (* Update Docker service [service] to [image].
     We also tag it, so that if someone redeploys the stack.yml then it will
     still use this version. *)
  let deploy { tag; service } image =
    Current.all [
      Docker.tag ~tag image;
      Docker.service ~name:service ~image ()
    ]
end
module Build_toxis = Build.Make(Toxis_service)

module Packet_unikernel = struct
  (* Mirage unikernels running on packet.net *)

  module Docker = Current_docker.Default

  type build_info = {
    dockerfile : string;
    target : string;
    args : string list;
  }

  type binary = Docker.Image.t

  type deploy_info = {
    service : string;
  }

  let build  { dockerfile; target; args } src =
    let args = ("TARGET=" ^ target) :: args in
    let build_args = List.map (fun x -> ["--build-arg"; x]) args |> List.concat in
    let dockerfile = Current.return (`File (Fpath.v dockerfile)) in
    Docker.build (`Git src)
      ~build_args
      ~dockerfile
      ~label:target
      ~pull:true
      ~timeout

  let name { service } = service

  (* Deployment *)

  module Mirage_m1_a = Mirage.Make(Docker)

  let mirage_host_ssh = "root@147.75.204.215"

  let deploy { service } image =
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

(* [web_ui collapse_value] is a URL back to the deployment service, for links
   in status messages. *)
let web_ui =
  let base = Uri.of_string "https://deploy.ocamllabs.io/" in
  fun repo -> Uri.with_query' base ["repo", repo]

let docker dockerfile services =
  let build_info = { Toxis_service.dockerfile } in
  let deploys =
    services
    |> List.map (fun (branch, tag, service) -> branch, { Toxis_service.tag; service }) in
  (build_info, deploys)

let unikernel dockerfile ~target args services =
  let build_info = { Packet_unikernel.dockerfile; target; args } in
  let deploys =
    services
    |> List.map (fun (branch, service) -> branch, { Packet_unikernel.service }) in
  (build_info, deploys)

(* This is a list of GitHub repositories to monitor.
   For each one, it lists the builds that are made from that repository.
   For each build, it says which which branch gives the desired live version of
   the service, and where to deloy it. *)
let v ~app ~notify:channel () =
  let ocurrent = Build.org ~app ~account:"ocurrent" 6853813 in
  let mirage = Build.org ~app ~account:"mirage" 7175142 in
  let docker_services = 
    let build (org, name, builds) = Build_toxis.repo ~channel ~web_ui ~org ~name builds in
    Current.all @@ List.map build [
      (* OCurrent repositories *)
      ocurrent, "ocaml-ci", [
        docker "Dockerfile"     ["live-engine", "ocaml-ci-service:latest", "ocaml-ci_ci"];
        docker "Dockerfile.web" ["live-www",    "ocaml-ci-web:latest",     "ocaml-ci_web";
                                 "staging-www", "ocaml-ci-web:staging",    "test-www"];
      ];
      ocurrent, "ocurrent-deployer", [
        docker "Dockerfile"     ["live", "ci.ocamllabs.io-deployer:latest", "infra_deployer"];
      ];
      ocurrent, "docker-base-images", [
        docker "Dockerfile"     ["live", "base-images:latest", "base-images_builder"];
      ];
      ocurrent, "opam-repo-ci", [
        docker "Dockerfile"     [];     (* No deployments for now *)
        docker "Dockerfile.web" [];
      ];
    ]
  and mirage_unikernels =
    let build (org, name, builds) = Build_unikernel.repo ~channel ~web_ui ~org ~name builds in
    Current.all @@ List.map build [
      mirage, "mirage-www", [
        unikernel "Dockerfile" ~target:"hvt" ["EXTRA_FLAGS=--tls=true"] ["master", "www"];
        unikernel "Dockerfile" ~target:"xen" ["EXTRA_FLAGS=--tls=true"] [];     (* (no deployments) *)
      ];
    ]
  in
  Current.all [ docker_services; mirage_unikernels ]
