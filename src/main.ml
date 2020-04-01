(* This is the main entry-point for the executable.
   Edit [cmd] to set the text for "--help" and modify the command-line interface. *)

let () =
  Unix.putenv "DOCKER_BUILDKIT" "1";
  Logging.init ()

let webhooks = [
  "github", Current_github.input_webhook
]

let read_channel_uri path =
  try
    let ch = open_in path in
    let uri = input_line ch in
    close_in ch;
    Current_slack.channel (Uri.of_string (String.trim uri))
  with ex ->
    Fmt.failwith "Failed to read slack URI from %S: %a" path Fmt.exn ex

let main config mode app slack =
  let installation = Current_github.App.installation app ~account:"ocurrent" 6853813 in
  let github = Current_github.Installation.api installation in
  let channel = read_channel_uri slack in
  let engine = Current.Engine.create ~config (Pipeline.v ~github ~notify:channel) in
  Logging.run begin
    Lwt.choose [
      Current.Engine.thread engine;  (* The main thread evaluating the pipeline. *)
      Current_web.run ~mode ~webhooks engine;  (* Optional: provides a web UI *)
    ]
  end

(* Command-line parsing *)

open Cmdliner

let slack =
  Arg.required @@
  Arg.opt Arg.(some file) None @@
  Arg.info
    ~doc:"A file containing the URI of the endpoint for status updates"
    ~docv:"URI-FILE"
    ["slack"]

let cmd =
  let doc = "build and deploy services from Git" in
  Term.(const main $ Current.Config.cmdliner $ Current_web.cmdliner $ Current_github.App.cmdliner $ slack),
  Term.info "deploy" ~doc

let () = Term.(exit @@ eval cmd)
