(* This is the main entry-point for the executable.
   Edit [cmd] to set the text for "--help" and modify the command-line interface. *)

let () = Logging.init ()

let main config mode repo =
  let repo = Current_git.Local.v (Fpath.v repo) in
  let engine = Current.Engine.create ~config (Pipeline.v ~repo) in
  Logging.run begin
    Lwt.choose [
      Current.Engine.thread engine;  (* The main thread evaluating the pipeline. *)
      Current_web.run ~mode engine;  (* Optional: provides a web UI *)
    ]
  end

(* Command-line parsing *)

open Cmdliner

(* An example command-line argument: the repository to monitor *)
let repo =
  Arg.required @@
  Arg.pos 0 Arg.(some dir) None @@
  Arg.info
    ~doc:"The directory containing the .git subdirectory."
    ~docv:"DIR"
    []

let cmd =
  let doc = "an OCurrent pipeline" in
  Term.(const main $ Current.Config.cmdliner $ Current_web.cmdliner $ repo),
  Term.info "example" ~doc

let () = Term.(exit @@ eval cmd)
