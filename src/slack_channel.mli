type mode = All | Failure
type t = { uri : Current_slack.channel; mode : mode; }

val parse_json : string -> t list
