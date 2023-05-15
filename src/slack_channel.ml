type mode =
  | All
  | Failure

type t = { uri : Current_slack.channel; mode : mode }

let mode_of_json_string t =
  let open Yojson.Safe in
  match Util.to_string t with
  | "all" -> All
  | "failure" -> Failure
  | _ -> raise (Util.Type_error ("\"mode\" must be: \"all\", or \"failure\"", t))

let parse_json s =
  let open Yojson.Safe in
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
    { uri; mode }
  in
  try
    from_string s |> Util.to_list |> List.map read_channel
  with ex ->
    Fmt.failwith "Failed to parse slack URIs '%S': %a" s Fmt.exn ex
