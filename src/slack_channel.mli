type mode = All | Failure
(** The condition on which we send a Slack message *)

type t = { uri : Current_slack.channel; mode : mode; }

val parse_json : string -> t list
