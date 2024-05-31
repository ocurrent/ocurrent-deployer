(** Build Docker images on registry.ci.dev *)

open Current.Syntax

let host = "registry.ci.dev"

module Docker = Current_docker.Make(struct let docker_context = Some host end)

let pool = Current.Pool.create ~label:"registry-build-pool" 1

type build_info = {
  dockerfile : string;
  timeout : int64;
}

type service = [
  | `Ocamlorg_opam4 of string
  | `Ocamlorg_opam5 of string
]

type deploy_info = {
  tag : string;
  services : service list;
}

let auth () = match Build.get_auth () with
  | Some (user, pass) -> Some (user ^ "@" ^ host, pass)
  | None -> None

let build_image { dockerfile; timeout } additional_build_args src =
  let src = Current_git.fetch src in
  let dockerfile = Current.return (`File (Fpath.v dockerfile)) in
  Current.component "commit SHA" |>
  let** additional_build_args = additional_build_args in
  let build_args = List.map (fun x -> ["--build-arg"; x]) additional_build_args |> List.concat in
  Docker.build (`Git src)
    ~pool
    ~build_args
    ~dockerfile
    ~pull:true
    ~timeout

let build { dockerfile; timeout } ?(additional_build_args=Current.return []) repo src =
  Metrics.Build.inc_builds "dockerregistry" repo;
  Current.ignore_value (build_image { dockerfile; timeout } additional_build_args src)

let name info = info.tag

(* Deployment *)

module Opam4_docker = Current_docker.Make(struct let docker_context = Some "opam-4.ocaml.org" end)
module Opam5_docker = Current_docker.Make(struct let docker_context = Some "opam-5.ocaml.org" end)

let no_schedule = Current_cache.Schedule.v ()

let pull_and_serve (module D : Current_docker.S.DOCKER) ~name repo_id =
  let image =
    Current.component "pull" |>
    let> repo_id in
    Current_docker.Raw.pull repo_id
    ?auth:(auth ())
    ~docker_context:D.docker_context
    ~schedule:no_schedule
    |> Current.Primitive.map_result (Result.map (fun raw_image ->
        D.Image.of_hash (Current_docker.Raw.Image.hash raw_image)
      ))
  in
  D.service ~name ~image ()

let deploy build_info { tag; services } ?(additional_build_args=Current.return []) src =
  let image = build_image build_info additional_build_args src in
  let tag = host ^ "/" ^ tag in
  Metrics.Build.inc_deployments "dockerregistry" tag;
  let repo_id = Docker.push ~tag image ?auth:(auth ()) in
  Current.all (
    List.map (fun service ->
      match service with
      | `Ocamlorg_opam4 name -> pull_and_serve ~name (module Opam4_docker) repo_id
      | `Ocamlorg_opam5 name -> pull_and_serve ~name (module Opam5_docker) repo_id
    ) services
  )
