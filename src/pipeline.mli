val v :
  ?app:Current_github.App.t ->
  ?notify:Current_slack.channel ->
  ?filter:(Current_github.Repo_id.t -> bool) ->
  sched:Current_ocluster.Connection.t ->
  staging_auth:(string * string) option ->
  unit -> unit Current.t
(** [v ~app ~notify ~sched ~staging_auth ()] is a pipeline that keeps the services up-to-date.
    @param staging_auth: [user, password] pair for pushing to staging repository. *)
