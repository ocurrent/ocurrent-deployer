(** Keep a Docker Compose v2 deployment up-to-date, pinning built images by
    digest into the compose file.

    Unlike {!Current_docker.S.DOCKER.compose_cli}, this supports multiple
    dependent images keyed by name and can read the [docker-compose.yml]
    straight from the build source (e.g. a Git checkout) rather than only from
    an in-memory string. *)

type source = [
  | `No_context
  | `Dir of Fpath.t Current.t
  | `Git of Current_git.Commit.t Current.t
]

module Raw : sig
  val compose_v2 :
    ?docker_compose_file:[`File of Fpath.t | `Contents of string] ->
    ?path:Fpath.t ->
    ?pull:bool ->
    ?detach:bool ->
    ?up_args:string list ->
    docker_context:string option ->
    project_name:string ->
    repos:Repo.t list ->
    [ `Git of Current_git.Commit.t | `Dir of Fpath.t | `No_context ] ->
    unit Current.Primitive.t
end

val compose_v2 :
  ?docker_compose_file:[`File of Fpath.t | `Contents of string] Current.t ->
  ?path:Fpath.t ->
  ?pull:bool ->
  ?detach:bool ->
  ?up_args:string list ->
  docker_context:string option ->
  project_name:string ->
  repos:(string * Current_docker.Raw.Image.t Current.t) list ->
  source ->
  unit Current.t
(** [compose_v2 ~docker_context ~project_name ~repos src] keeps a Docker
    Compose v2 deployment up-to-date.

    [src] provides the build context; with a [`Git] source and the default
    [docker_compose_file] of [`File "docker-compose.yml"], the compose file is
    read from the checked-out repository. For each [(name, image)] in [repos],
    the first occurrence of [name] in the compose file is replaced with
    [image]'s pinned digest reference before running {e docker compose pull}
    (when [pull] is set) and {e docker compose up}.

    @param docker_compose_file [`File path] to read from the source, or
           [`Contents yaml] to use a literal compose file (default
           [`File "docker-compose.yml"]).
    @param path Sub-directory within the source to run from.
    @param pull Whether to {e docker compose pull} first (default [true]).
    @param detach Pass [-d] to {e docker compose up} (default [true]).
    @param up_args Extra arguments appended to {e docker compose up}. *)

(** {2 Repositories} *)

module Repo = Repo
