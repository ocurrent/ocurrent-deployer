(** Mirage unikernels running on packet.net *)

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
    ~timeout:Build.timeout

let build info ?additional_build_args:_ repo src =
Metrics.Build.inc_builds "packetunikernel" repo;
Current.ignore_value (build_image info src)

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
  Metrics.Build.inc_deployments "packetunikernel" tag;
  Current.all [
    Docker.tag ~tag image;
    Mirage_m1_a.deploy ~name:service ~ssh_host:mirage_host_ssh image;
  ]