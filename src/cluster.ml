open Current.Syntax

module Arch = struct
  type t = [
    | `Linux_arm64
    | `Linux_x86_64
    | `Linux_ppc64
    | `Linux_s390x
    | `Linux_riscv64
    ]

  let pool_id : t -> string = function
    | `Linux_arm64 -> "linux-arm64"
    | `Linux_x86_64 -> "linux-x86_64"
    | `Linux_ppc64 -> "linux-ppc64"
    | `Linux_s390x -> "linux-s390x"
    | `Linux_riscv64 -> "linux-riscv64"

  let to_string : t -> string = function
    | `Linux_arm64 -> "arm64"
    | `Linux_x86_64 -> "x86_64"
    | `Linux_ppc64 -> "ppc64"
    | `Linux_s390x -> "s390x"
    | `Linux_riscv64 -> "riscv64"
end

let push_repo = "ocurrentbuilder/staging"

type build_info = {
  sched : Current_ocluster.t;
  dockerfile : [`Contents of string Current.t | `Path of string];
  options : Cluster_api.Docker.Spec.options;
  archs : Arch.t list;
}

type service = {
  name : string;
  docker_context : (module Current_docker.S.DOCKER);
  uri : string option;
}

type deploy_info = {
  hub_id : Cluster_api.Docker.Image_id.t;
  services : service list;
}

let show_service (org, name, builds) =
  let builds =
    List.map
      (fun (build, _deploys) ->
        Printf.sprintf "%s" (Cluster_api.Docker.Image_id.to_string build))
      builds
    |> String.concat "\n"
  in
  Printf.sprintf "- %s/%s\n%s" (Build.account org) name builds

let get_job_id x =
  let+ md = Current.Analysis.metadata x in
  match md with
  | Some { Current.Metadata.job_id; _ } -> job_id
  | None -> None

let unwrap = function
  | `Path _ as x -> Current.return x
  | `Contents x -> Current.map (fun x -> `Contents x) x

let component_label label dockerfile pool =
  let pp_label = Fmt.(option (cut ++ string)) in
  match dockerfile with
  | `Path path -> Current.component "build %s@,%s%a" path pool pp_label label
  | `Contents _ -> Current.component "build@,%s%a" pool pp_label label

let ocluster_build ?level ?label ?cache_hint t ~pool ~src ~options dockerfile =
  component_label label dockerfile pool |>
  let> dockerfile = unwrap dockerfile
  and> options
  and> src in
  Current_ocluster.Raw.build ?level ?cache_hint t ~pool ~src ~options dockerfile

(* Build [src/dockerfile] as a Docker service. *)
let build { sched; dockerfile; options; archs } ?(additional_build_args=Current.return []) repo src =
  let options =
    let+ additional_build_args = additional_build_args in
    { options with build_args = additional_build_args @ options.build_args }
  in
  Metrics.Build.inc_builds "cluster" repo;
  let hash = Current.map Current_git.Commit_id.hash src in
  let build_arch arch =
    let src = Current.map (fun x -> [x]) src in
    let pool = Arch.pool_id arch in
    let build = ocluster_build sched ~options ~pool ~src dockerfile in
    let index =
      let+ job_id = get_job_id build
      and+ hash in
      let label =
        match dockerfile with
        | `Path path -> Fmt.str "build %s@,%s" path pool
        | `Contents _ -> Fmt.str "build@,%s" pool
      in
      Index.record ~repo ~hash [(label, job_id)]
    in
    Current.all [build; index]
  in
  Current.all (List.map build_arch archs)

let name info = Cluster_api.Docker.Image_id.to_string info.hub_id

let no_schedule = Current_cache.Schedule.v ()

let docker_module context : (module Current_docker.S.DOCKER) =
  match context with
  | None -> (module Current_docker.Default)
  | Some _ -> (module Current_docker.Make(struct let docker_context = context end))

let pull_and_serve op repo_id {docker_context; name; _} =
  let module D = (val docker_context) in
  let image =
    Current.component "pull" |>
    let> repo_id in
    Current_docker.Raw.pull repo_id ?auth:(Build.get_auth ()) ~docker_context:D.docker_context ~schedule:no_schedule
    |> Current.Primitive.map_result (Result.map (fun raw_image ->
        D.Image.of_hash (Current_docker.Raw.Image.hash raw_image)
      ))
  in
  match op with
  | `Service -> D.service ~name ~image ()
  | `Compose contents ->
      let contents = Current.map (fun image ->
        Caddy.replace_hash_var ~hash:(D.Image.hash image) contents) image in
      D.compose_cli ~name ~contents ~detach:true ()
  | `Compose_cli contents ->
      let contents = Current.map (fun hash ->
        Aws.replace_hash_var ~hash contents) repo_id in
      D.compose_cli ~name ~contents ~detach:false ()

let build_and_push ?level ?label ?cache_hint t ~push_target ~pool ~src ~options dockerfile =
  component_label label dockerfile pool |>
  let> dockerfile = unwrap dockerfile
  and> options
  and> src in
  Current_ocluster.Raw.build_and_push ?level ?cache_hint t ~push_target ~pool ~src ~options dockerfile

let deploy { sched; dockerfile; options; archs } { hub_id; services } ?(additional_build_args=Current.return []) src =
  let src = Current.map (fun x -> [x]) src in
  let image_label = Cluster_api.Docker.Image_id.repo hub_id in
  Metrics.Build.inc_deployments "cluster" image_label;
  let target_label = String.map (function '/' | ':' -> '-' | c -> c) image_label in
  let options =
    let+ additional_build_args = additional_build_args in
    { options with build_args = additional_build_args @ options.build_args }
  in
  let build_arch arch =
    let pool = Arch.pool_id arch in
    let tag = Printf.sprintf "live-%s-%s" target_label pool in
    let push_target = Cluster_api.Docker.Image_id.v ~repo:push_repo ~tag in
    build_and_push sched ~options ~push_target ~pool ~src dockerfile
  in
  let images = List.map build_arch archs in
  match Build.get_auth () with
  | None -> Current.all (Current.fail "No auth configured; can't push final image" :: List.map Current.ignore_value images)
  | Some auth ->
    let multi_hash = Current_docker.push_manifest ~auth images ~tag:(Cluster_api.Docker.Image_id.to_string hub_id) in
    match services with
    | [] -> Current.ignore_value multi_hash
    | services ->
      services
      |> List.map (pull_and_serve `Service multi_hash)
      |> Current.all
