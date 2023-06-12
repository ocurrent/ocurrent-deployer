type mode = All | Failure
(** The condition on which we send a Slack message *)

type repositories = All_repos | Some_repos of string list
(** The set of repos that we send Slack messages for *)

type t = { uri : Current_slack.channel; mode : mode; repositories : repositories }

val parse_json : string -> t list
(** [parse_json s] parses the JSON string [s], the format of which is a list of objects with fields:

    - [uri], the URI endpoint for the Slack application, of the form 
      ["https://hooks.slack.com/services/***/***/***"]
    - [mode], which is the condition on which we send a Slack message. 
      ["all"] corresponds to [All], ["failure"] corresponds to [Failure]
    - [repositories], an optional parameter. If it is not present, then 
      we apply the record to all repositories being deployed. If it is 
      present, then it must contain a list of repositories, each being 
      represented as a string of the format ["org/repo"], e.g. 
      ["ocurrent/ocaml-ci"].

    Here is an example of a valid JSON string:
    {[
    \[
      {
        uri:"https://hooks.slack.com/services/***/***/***",
        mode:"failure",
        repositories:["ocurrent/ocaml-ci", "ocurrent/opam-repo-ci"]
      },
      {
        uri:"https://hooks.slack.com/services/***/***/***",
        mode:"all"
      }
    \]
    ]}

    The first record in the list says that when there is a deploy 
    failure on the [ocurrent/ocaml-ci] or the [ocurrent/opam-repo-ci] 
    repos, send a Slack message to the specified URI.

    The second record says that for every repo, for each event on the 
    deployment of those repos (successes and failures), send a Slack 
    message to the specified URI. *)
