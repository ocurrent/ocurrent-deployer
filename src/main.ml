(* This is the main entry-point for the executable.
   Edit [cmd] to set the text for "--help" and modify the command-line interface. *)

let () = Logging.init ()

let read_first_line path =
  let ch = open_in path in
  Fun.protect (fun () -> input_line ch)
    ~finally:(fun () -> close_in ch)

let read_channel_uri path =
  try
    let uri = read_first_line path in
    Current_slack.channel (Uri.of_string (String.trim uri))
  with ex ->
    Fmt.failwith "Failed to read slack URI from %S: %a" path Fmt.exn ex

(* Access control policy. *)
let has_role user role =
  match user with
  | None -> role = `Viewer || role = `Monitor         (* Unauthenticated users can only look at things. *)
  | Some user ->
    match Current_web.User.id user, role with
    | ("github:talex5"
      |"github:hannesm"
      |"github:avsm"
      |"github:kit-ty-kate"
      |"github:samoht"
      ), _ -> true        (* These users have all roles *)
    | _ -> role = `Viewer

let main config mode app slack auth =
  let channel = read_channel_uri slack in
  let engine = Current.Engine.create ~config (Pipeline.v ~app ~notify:channel) in
  let authn = Option.map Current_github.Auth.make_login_uri auth in
  let has_role =
    if auth = None then Current_web.Site.allow_all
    else has_role
  in
  let routes =
    Routes.(s "login" /? nil @--> Current_github.Auth.login auth) ::
    Routes.(s "webhooks" / s "github" /? nil @--> Current_github.webhook) ::
    Current_web.routes engine in
  let site = Current_web.Site.v ?authn ~has_role ~name:"OCurrent Deployer" routes in
  Logging.run begin
    Lwt.choose [
      Current.Engine.thread engine;  (* The main thread evaluating the pipeline. *)
      Current_web.run ~mode site;
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
  Term.(const main $ Current.Config.cmdliner $ Current_web.cmdliner $
        Current_github.App.cmdliner $ slack $ Current_github.Auth.cmdliner),
  Term.info "deploy" ~doc

let () = Term.(exit @@ eval cmd)
