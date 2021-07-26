open Capnp_rpc_lwt

val v :
  ?app:Current_github.App.t ->
  ?notify:Current_slack.channel ->
  ?filter:(Current_github.Repo_id.t -> bool) ->
  sched:[`Submission_f4e8a768b32a7c42] Sturdy_ref.t ->
  staging_auth:(string * string) option ->
  unit -> unit Current.t
(** [v ~app ~notify ~sched ~staging_auth ()] is a pipeline that keeps the services up-to-date.
    @param staging_auth: [user, password] pair for pushing to staging repository. *)
