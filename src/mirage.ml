open Lwt.Infix
open Current.Syntax

module Op = struct
  type t = {
    ssh_host : string;
  }

  let id = "mirage-deploy"

  module Key = Current.String
  module Value = Current.String
  module Outcome = Current.Unit

  let re_valid_name = Str.regexp "^[A-Za-z][-0-9A-Za-z_]*$"

  let validate_name name =
    if not (Str.string_match re_valid_name name 0) then
      Fmt.failwith "Invalid unikernel name %S" name

  let ssh t cmd =
    let cmd = "ssh" :: t.ssh_host :: cmd in
    ("", Array.of_list cmd)

  let publish t job name image =
    Current.Job.log job "Deploy %a -> %s" Value.pp image name;
    validate_name name;
    Current.Job.start job ~level:Current.Level.Dangerous >>= fun () ->
    let cmd = ["/usr/local/bin/deploy-mirage"; name; image] in
    Current.Process.exec ~cancellable:true ~job (ssh t cmd)

  let pp f (key, _v) = Fmt.pf f "@[<v2>deploy %a@]" Key.pp key

  let auto_cancel = true
end

module Deploy = Current_cache.Output(Op)

module Make(Docker : Current_docker.S.DOCKER) = struct
  type t = Op.t

  let config ~ssh_host () =
    { Op.ssh_host }

  let deploy t ~name image =
    Current.component "deploy %s" name |>
    let> image = image in
    Deploy.set t name (Docker.Image.hash image)
end
