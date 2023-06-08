type mode = All | Failure
(** The condition on which we send a Slack message *)


type repositories = All_repos | Some_repos of string list

type t = { uri : Current_slack.channel; mode : mode; repositories : repositories }

val parse_json : string -> t list
