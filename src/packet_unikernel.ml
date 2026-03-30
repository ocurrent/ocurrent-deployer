(** Mirage unikernels built via OCluster and deployed to packet.net *)

open Current.Syntax

let push_repo = "ocurrentbuilder/staging"

type build_info = {
  sched : Current_ocluster.t;
  dockerfile : string;
  target : string;
  args : string list;
}

type deploy_info = {
  service : string;
}

type service_info =
  Build.org * string * (build_info * (string * deploy_info) list) list

let build_and_push { sched; dockerfile; target; args } src =
  let src = Current.map (fun x -> [x]) src in
  let options = Current.return {
    Cluster_api.Docker.Spec.defaults with
    build_args = ("TARGET=" ^ target) :: args;
  } in
  let tag = Printf.sprintf "live-mirage-%s" target in
  let push_target = Cluster_api.Docker.Image_id.v ~repo:push_repo ~tag in
  let pool = "linux-x86_64" in
  Current.component "build %s@,%s" target pool |>
  let> options
  and> src in
  let cache_hint = "mirage-www-" ^ target in
  Current_ocluster.Raw.build_and_push sched ~cache_hint ~pool ~src ~options ~push_target
    (`Path dockerfile)

let build info ?additional_build_args:_ repo src =
  Metrics.Build.inc_builds "packetunikernel" repo;
  Current.ignore_value (build_and_push info src)

let name { service } = service

(* Deployment *)

let mirage_host_ssh = "root@147.75.84.37"

let deploy build_info { service } ?additional_build_args:_ src =
  let repo_id = build_and_push build_info src in
  let tag = "mirage-" ^ service in
  Metrics.Build.inc_deployments "packetunikernel" tag;
  Mirage.deploy_from_registry ~name:service ~ssh_host:mirage_host_ssh repo_id
