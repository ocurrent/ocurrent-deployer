val v : app:Current_github.App.t -> notify:Current_slack.channel -> unit -> unit Current.t
(** [v ~app ~notify ()] is a pipeline that keeps the services up-to-date. *)
