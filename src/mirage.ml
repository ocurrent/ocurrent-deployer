open Lwt.Infix
open Current.Syntax

module Raw = Current_docker.Raw

let with_tmp ~prefix ~suffix fn =
    let tmp_path = Filename.temp_file prefix suffix in
    Lwt.finalize
      (fun () -> fn tmp_path)
      (fun () ->
         Unix.unlink tmp_path;
         Lwt.return_unit
      )

let ( >>!= ) = Lwt_result.bind

module Op = struct
  type t = No_context

  let id = "mirage-deploy"

  module Key = struct
    type t = {
      name : string;
      ssh_host : string;
      docker_context : string option;
    } [@@deriving to_yojson]

    let digest t = Yojson.Safe.to_string (to_yojson t)
  end

  module Value = Raw.Image
  module Outcome = Current.Unit

  let re_valid_name = Str.regexp "^[A-Za-z][-0-9A-Za-z_]*$"

  let validate_name name =
    if not (Str.string_match re_valid_name name 0) then
      Fmt.failwith "Invalid unikernel name %S" name

  let redeploy ~ssh_host name =
    let cmd = ["ssh"; ssh_host; "mirage-redeploy"; name] in
    ("", Array.of_list cmd)

  let run image = Raw.Cmd.docker ["container"; "run"; "-d"; Raw.Image.hash image]
  let docker_cp src dst = Raw.Cmd.docker ["cp"; src; dst]

  let rsync src dst =
    let cmd = [| "rsync"; "-vi"; src; dst |] in
    ("", cmd)

  let publish No_context job { Key.name; ssh_host; docker_context } image =
    Current.Job.log job "Deploy %a -> %s" Value.pp image name;
    validate_name name;
    Current.Job.start job ~level:Current.Level.Dangerous >>= fun () ->
    (* Extract unikernel image from Docker image: *)
    with_tmp ~prefix:"ocurrent-deployer-" ~suffix:".hvt" @@ fun tmp_path ->
    Raw.Cmd.with_container ~docker_context ~job ~kill_on_cancel:true (run image ~docker_context) (fun id ->
        let src = Printf.sprintf "%s:/unikernel.hvt" id in
        Current.Process.exec ~cancellable:true ~job (docker_cp ~docker_context src tmp_path)
      ) >>!= fun () ->
    (* rsync to remote host: *)
    let remote_path = Printf.sprintf "%s:/srv/unikernels/%s.hvt" ssh_host name in
    Current.Process.exec ~cancellable:true ~job (rsync tmp_path remote_path) >>!= fun () ->
    (* Restart remote service: *)
    Current.Process.exec ~cancellable:true ~job (redeploy ~ssh_host name)

  let pp f (key, _v) = Fmt.pf f "@[<v2>deploy %s@]" key.Key.name

  let auto_cancel = true
end

module Deploy = Current_cache.Output(Op)

module Make(Docker : Current_docker.S.DOCKER) = struct
  let deploy ~name ~ssh_host image =
    Current.component "deploy %s" name |>
    let> image in
    let docker_context = Docker.docker_context in
    Deploy.set Op.No_context { Op.Key.name; ssh_host; docker_context } (Docker.Image.hash image |> Raw.Image.of_hash)
end
