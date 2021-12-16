module Metrics = struct
  open Prometheus

  let namespace = "baseimages"

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

let pp_timestamp f x =
  let open Unix in
  let tm = localtime x in
  Fmt.pf f "%04d-%02d-%02d %02d:%02d.%02d" (tm.tm_year + 1900) (tm.tm_mon + 1)
    tm.tm_mday tm.tm_hour tm.tm_min tm.tm_sec

let reporter =
  let report src level ~over k msgf =
    let k _ = over (); k () in
    let src = Logs.Src.name src in
    Metrics.inc_messages level src;
    msgf @@ fun ?header ?tags:_ fmt ->
    Fmt.kpf k Fmt.stdout ("%a %a %a @[" ^^ fmt ^^ "@]@.")
      pp_timestamp (Unix.gettimeofday ())
      Fmt.(styled `Magenta string) (Printf.sprintf "%14s" src)
      Logs_fmt.pp_header (level, header)
  in
  { Logs.report = report }

let init style_renderer level =
  Fmt_tty.setup_std_outputs ?style_renderer ();
  Logs.set_level level;
  Logs.set_reporter reporter

let cmdliner =
  Cmdliner.(Term.(const init $ Fmt_cli.style_renderer () $ Logs_cli.level ()))

let run x =
  match Lwt_main.run x with
  | Ok () -> Ok ()
  | Error (`Msg m) as e ->
    Logs.err (fun f -> f "%a" Fmt.lines m);
    e
