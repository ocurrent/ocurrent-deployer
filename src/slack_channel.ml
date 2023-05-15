type mode =
  | Success
  | Failure
  | Both

type t = { uri : Current_slack.channel; mode : mode }

let mode_of_json_string t =
  let open Yojson.Safe in
  match Util.to_string t with
  | "success" -> Success
  | "failure" -> Failure
  | "both" -> Both
  | _ -> raise (Util.Type_error ("\"mode\" must be any of: \"success\", \"failure\", or \"both\"", t))

let v uri mode = { uri; mode }
