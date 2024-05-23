open Deployer

let has_deployments t =
  List.exists
    (fun t -> t.Pipeline.services != [])
    t.Pipeline.targets

let output_archs archs =
  String.concat ", " @@ List.map Cluster.Arch.to_string archs

let output_docker t =
  if not (has_deployments t) then []
  else
    let header = [
      Printf.sprintf "- `%s` on arches: %s" t.dockerfile (output_archs t.archs)
    ] in
    let deployments =
      List.map (fun t -> Printf.sprintf "  - branch `%s` at `%s`" t.Pipeline.branch t.target) t.targets 
    in
    header @ deployments

let output_service (org, name, dockers) =
  if List.for_all (fun x -> not (has_deployments x)) dockers then None
  else
    let header = [ Printf.sprintf "### %s/%s" (Build.account org) name ] in
    let dockers =
      List.map output_docker dockers
      |> List.flatten
      (* |> List.map (fun x -> "  " ^ x) *)
    in
    Some (String.concat "\n" (header @ dockers))

let main outfile =
  let oc = open_out outfile in
  Printf.fprintf oc "## Deployed CI services\n\n";
  Pipeline.Tarides.services ()
  |> List.filter_map output_service
  |> List.iter (Printf.fprintf oc "%s\n\n");
  close_out oc

(* Command-line parsing *)
open Cmdliner

let outfile =
  Arg.required @@
  Arg.opt Arg.(some string) None @@
  Arg.info
    ~doc:"The destination file for the list of services."
    ~docv:"OUTFILE"
    ["out"; "o"]

let cmd =
  let doc = "Generate documentation for the list of services" in
  let info = Cmd.info "doc" ~doc in
  let cmd_t = Term.(const main $ outfile) in
  Cmd.v info cmd_t

let () = exit (Cmd.eval cmd)
