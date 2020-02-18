val v : github:Current_github.Api.t -> notify:Current_slack.channel -> unit -> unit Current.t
(** [v ~github ~notify ()] is a pipeline that keeps the services up-to-date. *)
