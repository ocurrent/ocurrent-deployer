(* This is the main entry-point for the service. *)

open Deployer

(* A low-security Docker Hub user used to push images to the staging area.
   Low-security because we never rely on the tags in this repository, just the hashes. *)
let staging_user = "ocurrentbuilder"

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

let main () config mode app slack auth staging_password_file ((deployer : Pipeline.deployer), sched) prometheus_config =
  let vat = Capnp_rpc_unix.client_only_vat () in
  let channel = read_channel_uri slack in
  let staging_auth = staging_password_file |> Option.map (fun path -> staging_user, read_first_line path) in
  let authn = Option.map Current_github.Auth.make_login_uri auth in
  let webhook_secret = Current_github.App.webhook_secret app in
  let sched = Current_ocluster.Connection.create (Capnp_rpc_unix.Vat.import_exn vat sched) in
  let engine = Current.Engine.create ~config (fun () -> deployer.pipeline ~app ~notify:channel ~sched ~staging_auth ()) in
  let has_role =
    if auth = None then
      Current_web.Site.allow_all
    else
      fun user role ->
        Access.user_has_role ~admins:deployer.admins (Option.map Current_web.User.id user) role
  in
  let routes =
    Routes.(s "login" /? nil @--> Current_github.Auth.login auth) ::
    Routes.(s "webhooks" / s "github" /? nil @--> Current_github.webhook ~engine ~get_job_ids:Index.get_job_ids ~webhook_secret) ::
    Current_web.routes engine in
  let site = Current_web.Site.v ?authn ~has_role ~name:"OCurrent Deployer" routes in
  let prometheus =
    List.map (Lwt.map @@ Result.ok) (Prometheus_unix.serve prometheus_config)
  in
  Logging.run begin
    Lwt.choose ([
      Current.Engine.thread engine;  (* The main thread evaluating the pipeline. *)
      Current_web.run ~mode site;
    ] @ prometheus)
  end

(* Command-line parsing *)
open Cmdliner

let slack =
  Arg.required @@
  Arg.opt Arg.(some file) None @@
  Arg.info
    ~doc:"A file containing the URI of the endpoint for status updates."
    ~docv:"URI-FILE"
    ["slack"]

let submission_service =
  Arg.value @@
  Arg.opt Arg.(some Capnp_rpc_unix.sturdy_uri) None @@
  Arg.info
    ~doc:"The submission.cap file for the build scheduler service."
    ~docv:"FILE"
    ["submission-service"]

let deployer_and_schedular =
  let f schedular deployer = match schedular with
    | Some sched -> `Ok (deployer, sched)
    | None -> `Error (true, "--submission-service is required with --flavour")
  in
  Term.(ret (const f $ submission_service $ Pipeline.cmdliner))

let staging_password =
  Arg.value @@
  Arg.opt Arg.(some file) None @@
  Arg.info
    ~doc:(Printf.sprintf "A file containing the password for the %S Docker Hub user." staging_user)
    ~docv:"FILE"
    ["staging-password-file"]

let cmd =
  let doc = "build and deploy services from Git" in
  let cmd_t = Term.(term_result (const main $ Logging.cmdliner $ Current.Config.cmdliner $ Current_web.cmdliner $
        Current_github.App.cmdliner $ slack $ Current_github.Auth.cmdliner $ staging_password $ deployer_and_schedular
        $ Prometheus_unix.opts)) in
  let info = Cmd.info "deploy" ~doc in
  Cmd.v info cmd_t

let () = exit (Cmd.eval cmd)
