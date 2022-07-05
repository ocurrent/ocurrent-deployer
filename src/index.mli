(** The index is:
    - A (persisted) map from each Git commit hash to its last known OCurrent job ID. *)

val init : unit -> unit
(** Ensure the database is initialised (for unit-tests). *)

val record :
  repo:Current_github.Repo_id.t ->
  hash:string ->
  (string * Current.job_id option) list ->
  unit
(** [record ~repo ~hash jobs] updates the entry for [repo, hash] to point at [jobs]. *)

val get_job_ids: owner:string -> name:string -> hash:string -> string list
(** list of job_ids that correspond to (owner, name, commit)*)