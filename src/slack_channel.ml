type mode =
  | All
  | Failure

type repositories =
  | All_repos
  | Some_repos of string list

type t = { uri : Current_slack.channel; mode : mode; repositories : repositories }

open Yojson.Safe

let mode_of_json_string t =
  let open Yojson.Safe in
  match Util.to_string t with
  | "all" -> All
  | "failure" -> Failure
  | _ -> raise (Util.Type_error ("\"mode\" must be: \"all\", or \"failure\"", t))

let repositories_of_json_string = function
  | `Null -> All_repos
  | l -> Some_repos (List.map Util.to_string @@ Util.to_list l)

let parse_json s =
  let read_channel ch =
    let uri =
      Util.(member "uri" ch |> to_string)
      |> String.trim
      |> Uri.of_string
      |> Current_slack.channel in
    let mode =
      Util.member "mode" ch
      |> mode_of_json_string
    in
    let repositories =
      Util.member "repositories" ch
      |> repositories_of_json_string
    in
    { uri; mode; repositories }
  in
  try
    from_string s |> Util.to_list |> List.map read_channel
  with ex ->
    Fmt.failwith "Failed to parse slack URIs '%S': %a" s Fmt.exn ex
