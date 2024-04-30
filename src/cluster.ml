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
end

let password_path = "/run/secrets/ocurrent-hub"
let push_repo = "ocurrentbuilder/staging"

let auth =
  if Sys.file_exists password_path then (
    let ch = open_in_bin password_path in
    let len = in_channel_length ch in
    let password = really_input_string ch len |> String.trim in
    close_in ch;
    Some ("ocurrent", password)
  ) else (
    Fmt.pr "Password file %S not found; images will not be pushed to hub@." password_path;
    None
  )

(* Strings here represent the docker context to use. *)
module Ci3_docker = Current_docker.Default
module Ci4_docker = Current_docker.Make(struct let docker_context = Some "ci4.ocamllabs.io" end)
module Docs_docker = Current_docker.Make(struct let docker_context = Some "docs.ci.ocaml.org" end)
module Staging_docs_docker = Current_docker.Make(struct let docker_context = Some "staging.docs.ci.ocamllabs.io" end)
module Ci_docker = Current_docker.Make(struct let docker_context = Some "ocaml.ci.dev" end)
module Opamrepo_docker = Current_docker.Make(struct let docker_context = Some "opam.ci.ocaml.org" end)
module Check_docker = Current_docker.Make(struct let docker_context = Some "check.ci.ocaml.org" end)
module Watch_docker = Current_docker.Make(struct let docker_context = Some "watch.ocaml.org" end)
module Ocamlorg_docker = Current_docker.Make(struct let docker_context = Some "ocaml-www1" end)
module Cimirage_docker = Current_docker.Make(struct let docker_context = Some "ci.mirage.io" end)
module V2ocamlorg_docker = Current_docker.Make(struct let docker_context = Some "v2.ocaml.org" end)
module Ocamlorg_images = Current_docker.Make(struct let docker_context = Some "ci3.ocamllabs.io" end)
module Docker_aws = Current_docker.Make(struct let docker_context = Some "awsecs" end)
module V3b_docker = Current_docker.Make(struct let docker_context = Some "v3b.ocaml.org" end)
module V3c_docker = Current_docker.Make(struct let docker_context = Some "v3c.ocaml.org" end)
module Deploycamlorg_docker = Current_docker.Default

type build_info = {
  sched : Current_ocluster.t;
  dockerfile : [`Contents of string Current.t | `Path of string];
  options : Cluster_api.Docker.Spec.options;
  archs : Arch.t list;
}

type service = [
(* Services on deploy.ci.dev *)
  | `Ci of string
  | `Opamrepo of string
  | `Check of string
  | `Ci3 of string
  | `Ci4 of string
  | `Docs of string
  | `Staging_docs of string

  (* Services on deploy.mirage.io *)
  | `Cimirage of string

  (* Services on deploy.ci.ocaml.org. *)
  | `Ocamlorg_deployer of string             (* OCurrent deployer @ deploy.ci.ocaml.org *)
  | `OCamlorg_v2 of (string * string option) list   (* OCaml website @ v2.ocaml.org *)
  | `Ocamlorg_images of string               (* Base Image builder @ images.ci.ocaml.org *)
  | `OCamlorg_v3b of string                  (* OCaml website @ v3b.ocaml.org aka www.ocaml.org *)
  | `OCamlorg_v3c of string                  (* Staging OCaml website @ staging.ocaml.org *)
  | `Aws_ecs of Aws.t                        (* Amazon Web Services - Elastic Container Service *)
]

type deploy_info = {
  hub_id : Cluster_api.Docker.Image_id.t;
  services : service list;
}

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

let pull_and_serve (module D : Current_docker.S.DOCKER) ~name op repo_id =
  let image =
    Current.component "pull" |>
    let> repo_id in
    Current_docker.Raw.pull repo_id ?auth ~docker_context:D.docker_context ~schedule:no_schedule
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

let pull_and_serve multi_hash hub_id = function
  (* deploy.ci.dev *)
  | `Ci3 name -> pull_and_serve (module Ci3_docker) ~name `Service multi_hash
  | `Ci4 name -> pull_and_serve (module Ci4_docker) ~name `Service multi_hash
  | `Docs name -> pull_and_serve (module Docs_docker) ~name `Service multi_hash
  | `Staging_docs name -> pull_and_serve (module Staging_docs_docker) ~name `Service multi_hash
  | `Ci name -> pull_and_serve (module Ci_docker) ~name `Service multi_hash
  | `Opamrepo name -> pull_and_serve (module Opamrepo_docker) ~name `Service multi_hash
  | `Check name -> pull_and_serve (module Check_docker) ~name `Service multi_hash
  (* deploy.mirage.io *)
  | `Cimirage name -> pull_and_serve (module Cimirage_docker) ~name `Service multi_hash
  (* ocaml.org *)
  | `Ocamlorg_deployer name -> pull_and_serve (module Deploycamlorg_docker) ~name `Service multi_hash
  | `OCamlorg_v2 domains ->
    let name = Cluster_api.Docker.Image_id.tag hub_id in
    let contents = Caddy.compose {Caddy.name; domains} in
    pull_and_serve (module V2ocamlorg_docker) ~name (`Compose contents) multi_hash
  | `Ocamlorg_images name -> pull_and_serve (module Ocamlorg_images) ~name `Service multi_hash
  | `OCamlorg_v3b name -> pull_and_serve (module V3b_docker) ~name `Service multi_hash
  | `OCamlorg_v3c name -> pull_and_serve (module V3c_docker) ~name `Service multi_hash
  | `Aws_ecs project ->
    let contents = Aws.compose project in
    pull_and_serve (module Docker_aws) ~name:(project.name ^ "-" ^ project.branch) (`Compose_cli contents) multi_hash

let deploy { sched; dockerfile; options; archs } { hub_id; services } ?(additional_build_args=Current.return []) src =
  let src = Current.map (fun x -> [x]) src in
  let target_label = Cluster_api.Docker.Image_id.repo hub_id |> String.map (function '/' | ':' -> '-' | c -> c) in
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
  match auth with
  | None -> Current.all (Current.fail "No auth configured; can't push final image" :: List.map Current.ignore_value images)
  | Some auth ->
    let multi_hash = Current_docker.push_manifest ~auth images ~tag:(Cluster_api.Docker.Image_id.to_string hub_id) in
    match services with
    | [] -> Current.ignore_value multi_hash
    | services ->
      services
      |> List.map (pull_and_serve multi_hash hub_id)
      |> Current.all
