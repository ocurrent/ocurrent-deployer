open Prometheus

let namespace = "deployer"

module Logs = struct
  let subsystem = "logs"

  let inc_messages =
    let help = "Total number of messages logged" in
    let c =
      Counter.v_labels ~label_names:[ "level"; "src" ] ~help ~namespace
        ~subsystem "messages_total"
    in
    fun lvl src ->
      let lvl = Logs.level_to_string (Some lvl) in
      Counter.inc_one @@ Counter.labels c [ lvl; src ]
end

module Build = struct
  let subsystem = "build"

  let repo_to_str r =
    Printf.sprintf "%s/%s" r.Current_github.Repo_id.owner r.name

  let inc_builds =
    let help = "Number of builds" in
    let c =
      Counter.v_labels ~help ~label_names:[ "type"; "service" ] ~namespace ~subsystem "builds_total"
    in
    fun t service ->
    Counter.inc_one @@ Counter.labels c [ t; repo_to_str service ]

  let inc_deployments =
    let help = "Number of deployments" in
    let c =
      Counter.v_labels ~help ~label_names:[ "type"; "service" ] ~namespace ~subsystem "deployments_total"
    in
    fun t service ->
    Counter.inc_one @@ Counter.labels c [ t; service ]
end
