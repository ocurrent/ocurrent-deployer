val v :
  app:Current_github.App.t ->
  notify:Current_slack.channel ->
  unit -> unit Current.t
(** [v ~app ~notify ~sched ~staging_auth ()] is a pipeline that keeps the services up-to-date.
    @param staging_auth: [user, password] pair for pushing to staging repository. *)
