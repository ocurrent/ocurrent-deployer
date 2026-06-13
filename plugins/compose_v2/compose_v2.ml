open Lwt.Infix

type t = {
  pull: bool ;
}

let id = "docker-compose-v2"

module Key = struct
  type t = {
    commit : [ `No_context | `Git of Current_git.Commit.t | `Dir of Fpath.t ];
    docker_context : string option;
    docker_compose_file : [`File of Fpath.t | `Contents of string];
    path : Fpath.t option;
    detach : bool;
    up_args: string list;
    project_name: string;
  }

  let digest_docker_compose_file = function
    | `File name -> `Assoc [ "file", `String (Fpath.to_string name) ]
    | `Contents contents -> `Assoc [ "contents", `String (Digest.string contents |> Digest.to_hex) ]

  let source_to_json = function
    | `No_context -> `Null
    | `Git commit -> `String (Current_git.Commit.hash commit)
    | `Dir path -> `String (Fpath.to_string path)

  let to_json { commit; docker_compose_file; docker_context; detach; project_name; up_args; path } =
    `Assoc [
      "commit", source_to_json commit;
      "docker_context", [%derive.to_yojson:string option] docker_context;
      "docker_compose_file", digest_docker_compose_file docker_compose_file;
      "path", Option.(value ~default:`Null (map (fun v -> `String (Fpath.to_string v)) path));
      "detach", [%derive.to_yojson:bool] detach;
      "up_args", [%derive.to_yojson:string list] up_args;
      "project_name", [%derive.to_yojson:string] project_name;
    ]

  let digest t = Yojson.Safe.to_string (to_json t)

  let pp f t = Yojson.Safe.pretty_print f (to_json t)
end

module Value = struct
  type t = {
    repos : Repo.t list;
  }

  let digest { repos } =
    Yojson.Safe.to_string @@ `Assoc [
      "image", `String (List.map (fun image -> Repo.digest image) repos |> String.concat ";");
    ]
end

module Outcome = Current.Unit

let or_raise = function
  | Ok x -> x
  | Error (`Msg m) -> raise (Failure m)

let with_context ~job context fn =
  let open Lwt_result.Infix in
  match context with
  | `No_context -> Current.Process.with_tmpdir ~prefix:"build-context-" fn
  | `Dir path ->
      Current.Process.with_tmpdir ~prefix:"build-context-" @@ fun dir ->
      Current.Process.exec ~cwd:dir ~cancellable:true ~job ("", [| "rsync"; "-aHq"; Fpath.to_string path ^ "/"; "." |]) >>= fun () ->
      fn dir
  | `Git commit -> Current_git.with_checkout ~job commit fn

let search_and_replace needle haystack replacement =
  match Astring.String.find_sub ~sub:needle haystack with
  | None -> haystack
  | Some len -> (Astring.String.with_range ~len haystack) ^ replacement ^ (Astring.String.with_range ~first:(len + String.length needle) haystack)

let publish { pull } job key { Value.repos } =
  let { Key.commit; docker_context; docker_compose_file; detach; up_args; project_name; path } = key in
  Current.Job.start job ~level:Current.Level.Dangerous >>= fun () ->
  with_context ~job commit @@ fun dir ->
  let dir = match path with
    | Some path -> Fpath.(dir // path)
    | None -> dir
  in
  let contents, name =
    match docker_compose_file with
    | `Contents contents -> contents ^ "\n", Fpath.(dir / "docker-compose.yml")
    | `File name -> Bos.OS.File.read Fpath.(dir // name) |> or_raise, name
  in
  let contents = List.fold_left (fun acc repo -> search_and_replace (Repo.name repo) acc (Repo.digest repo)) contents repos
  in
  let file =
    Bos.OS.File.write Fpath.(dir // name) contents |> or_raise;
    Current.Job.log job "@[<v2>%s\n%a@]" Fpath.(to_string name) Fmt.string contents;
    match docker_compose_file with
    | `Contents _ -> []
    | `File name -> ["-f"; Fpath.(to_string (dir // name))]
  in
  let args = ["compose"; "-p"; project_name] @ file in
  let p =
    if pull then Current.Process.exec ~cancellable:true ~job (Current_docker.Raw.Cmd.docker ~docker_context (args @ ["pull"]))
    else Lwt.return (Ok ())
  in
  p >>= function
  | Error _ as e -> Lwt.return e
  | Ok () -> Current.Process.exec ~cancellable:true ~job (Current_docker.Raw.Cmd.docker ~docker_context (args @ ["up"] @ (if detach then ["-d"] else []) @ up_args))

let pp f (key, value) =
  let { Key.commit = _; docker_context = _; docker_compose_file = _; path = _; detach = _; up_args = _; project_name } = key in
  Fmt.pf f "%s %s" project_name (Value.digest value)

let auto_cancel = false
