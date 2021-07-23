(* The ocurrent-deployer-local command, for testing changes locally. *)

let () = Logging.init ()

(* A low-security Docker Hub user used to push images to the staging area.
   Low-security because we never rely on the tags in this repository, just the hashes. *)
let staging_user = "ocurrentbuilder"

let read_first_line path =
  let ch = open_in path in
  Fun.protect (fun () -> input_line ch)
    ~finally:(fun () -> close_in ch)

let main config mode app sched staging_password_file =
  let vat = Capnp_rpc_unix.client_only_vat () in
  let sched = Capnp_rpc_unix.Vat.import_exn vat sched in
  let staging_auth = staging_password_file |> Option.map (fun path -> staging_user, read_first_line path) in
  let engine = Current.Engine.create ~config (Pipeline.v ?app ~sched ~staging_auth) in
  let routes =
    Routes.(s "webhooks" / s "github" /? nil @--> Current_github.webhook) ::
    Current_web.routes engine in
  let site = Current_web.Site.v ~has_role:Current_web.Site.allow_all ~name:"OCurrent Deployer" routes in
  Logging.run begin
    Lwt.choose [
      Current.Engine.thread engine;  (* The main thread evaluating the pipeline. *)
      Current_web.run ~mode site;
    ]
  end

(* Command-line parsing *)

open Cmdliner

let submission_service =
  Arg.required @@
  Arg.opt Arg.(some Capnp_rpc_unix.sturdy_uri) None @@
  Arg.info
    ~doc:"The submission.cap file for the build scheduler service"
    ~docv:"FILE"
    ["submission-service"]

let staging_password =
  Arg.value @@
  Arg.opt Arg.(some file) None @@
  Arg.info
    ~doc:(Printf.sprintf "A file containing the password for the %S Docker Hub user" staging_user)
    ~docv:"FILE"
    ["staging-password-file"]

let cmd =
  let doc = "build and deploy services from Git" in
  Term.(const main $ Current.Config.cmdliner $ Current_web.cmdliner $
        Current_github.App.cmdliner_opt $ submission_service $ staging_password),
  Term.info "deploy" ~doc

let () = Term.(exit @@ eval cmd)
