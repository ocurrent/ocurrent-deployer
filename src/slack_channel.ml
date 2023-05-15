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

let v uri mode = { uri; mode }
