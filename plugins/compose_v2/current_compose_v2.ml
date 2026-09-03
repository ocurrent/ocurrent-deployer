open Current.Syntax

module Repo = Repo

type source = [
  | `No_context
  | `Dir of Fpath.t Current.t
  | `Git of Current_git.Commit.t Current.t
]

module Raw = struct
  module CV2 = Current_cache.Output(Compose_v2)

  let compose_v2 ?docker_compose_file ?path ?(pull=true) ?(detach=true) ?(up_args = []) ~docker_context ~project_name ~repos commit =
    let docker_compose_file =
      match docker_compose_file with
      | None -> `File (Fpath.v "docker-compose.yml")
      | Some (`File _ as f) -> f
      | Some (`Contents c) -> `Contents c
    in
    CV2.set Compose_v2.{ pull }
      { Compose_v2.Key.commit; docker_compose_file; path; docker_context; detach; up_args; project_name }
      { Compose_v2.Value.repos }
end

let get_build_context = function
  | `No_context -> Current.return `No_context
  | `Git commit -> Current.map (fun x -> `Git x) commit
  | `Dir path -> Current.map (fun path -> `Dir path) path

let compose_v2 ?docker_compose_file ?path ?pull ?detach ?up_args ~docker_context ~project_name ~repos src =
  Current.component "docker-compose-v2@,%s" project_name |>
  let names, images = List.split repos in
  let> commit = get_build_context src
  and> images = Current.list_seq images
  and> docker_compose_file = Current.option_seq docker_compose_file in
  let repos = List.map2 (fun name image -> { Repo.name; image }) names images in
  Raw.compose_v2 ?docker_compose_file ?path ?pull ?detach ?up_args ~docker_context ~project_name ~repos commit
