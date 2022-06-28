(* The ocurrent-deployer-local command, for testing changes locally. *)

(* A low-security Docker Hub user used to push images to the staging area.
   Low-security because we never rely on the tags in this repository, just the hashes. *)
open Deployer

let staging_user = "ocurrentbuilder"

(* Placeholder webhook_secret, when running in local mode. *)
let webhook_secret = "local-secret"

let read_first_line path =
  let ch = open_in path in
  Fun.protect (fun () -> input_line ch)
    ~finally:(fun () -> close_in ch)

let main () config mode app sched staging_password_file repo flavour =
  Logs.info (fun f -> f "Is this thing on?");
  let filter = Option.map (=) repo in
  let vat = Capnp_rpc_unix.client_only_vat () in
  let sched = Current_ocluster.Connection.create (Capnp_rpc_unix.Vat.import_exn vat sched) in
  let staging_auth = staging_password_file |> Option.map (fun path -> staging_user, read_first_line path) in
  let engine = match flavour with
    | `Tarides -> Current.Engine.create ~config (Pipeline.tarides ?app ~sched ~staging_auth ?filter)
    | `OCaml -> Current.Engine.create ~config (Pipeline.ocaml_org ?app ~sched ~staging_auth ?filter)
    | `Toxis -> Current.Engine.create ~config (Pipeline.toxis ?app)
  in
  let webhook_secret = Option.value ~default:webhook_secret @@ Option.map Current_github.App.webhook_secret app in
  let has_role = Current_web.Site.allow_all in
  let routes =
    Routes.(s "webhooks" / s "github" /? nil @--> Current_github.webhook ~engine ~get_job_ids:Index.get_job_ids ~webhook_secret ~has_role) ::
    Current_web.routes engine in
  let site = Current_web.Site.v ~has_role ~name:"OCurrent Deployer" routes in
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

let repo =
  Arg.value @@
  Arg.pos 0 Arg.(some Current_github.Repo_id.cmdliner) None @@
  Arg.info
    ~doc:"The owner/name of the repository to test"
    ~docv:"REPO"
    []

let cmd =
  let doc = "build and deploy services from Git" in
  let cmd_t = Term.(term_result (const main $ Logging.cmdliner $ Current.Config.cmdliner $ Current_web.cmdliner
                    $ Current_github.App.cmdliner_opt $ submission_service $ staging_password $ repo $ Pipeline.Flavour.cmdliner)) in
  let info = Cmd.info "deploy" ~doc in
  Cmd.v info cmd_t

let () = exit @@ Cmd.eval cmd
