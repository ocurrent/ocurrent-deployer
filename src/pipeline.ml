open Current.Syntax

module Github = Current_github

let timeout = Duration.of_min 50    (* Max build time *)

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

let or_fail = function
  | Ok x -> x
  | Error (`Msg m) -> failwith m

type arch = [
  | `Linux_arm64
  | `Linux_x86_64
  | `Linux_ppc64
]

let pool_id : arch -> string = function
  | `Linux_arm64 -> "linux-arm64"
  | `Linux_x86_64 -> "linux-x86_64"
  | `Linux_ppc64 -> "linux-ppc64"

module Cluster = struct
  (* Strings here represent the docker context to use. *)
  (* module Ci3_docker = Current_docker.Default *)
  (* module Ci4_docker = Current_docker.Make(struct let docker_context = Some "ci4" end) *)
  (* module Ci6_docker = Current_docker.Make(struct let docker_context = Some "docsci" end) *)
  (* module Toxis_docker = Current_docker.Make(struct let docker_context = Some "toxis" end) *)
  (* module Tezos_docker = Current_docker.Make(struct let docker_context = Some "tezos" end) *)
  (* module Cb_docker = Current_docker.Make(struct let docker_context = Some "packet-current-bench" end) *)
  module Ocamlorg_docker = Current_docker.Make(struct let docker_context = Some "ocaml-www1" end)
  module V3ocamlorg_docker = Current_docker.Make(struct let docker_context = Some "v3-ocaml-org" end)
  (* module Deploycamlorg_docker = Current_docker.Make(struct let docker_context = Some "deploy-ocaml-org" end) *)
  module Deploycamlorg_docker = Current_docker.Default

  type build_info = {
    sched : Current_ocluster.t;
    dockerfile : [`Contents of string Current.t | `Path of string];
    options : Cluster_api.Docker.Spec.options;
    archs : arch list;
  }

  type service = [
    (* | `Toxis of string *)
    (* | `Tezos of string *)
    (* | `Ci3 of string *)
    (* | `Ci4 of string *)
    (* | `Ci6 of string *)
    (* | `Cb of string *)
    | `Ocamlorg_sw of (string * string) list
    | `V3ocamlorg_cl of string
    | `Ocamlorg_deployer of string (* OCurrent deployer @ deploy.ci.ocaml.org *)
  ]

  type deploy_info = {
    hub_id : Cluster_api.Docker.Image_id.t;
    services : service list;
  }

  (* Build [src/dockerfile] as a Docker service. *)
  let build { sched; dockerfile; options; archs } src =
    let src = Current.map (fun x -> [x]) src in
    let build_arch arch = Current_ocluster.build sched ~options ~pool:(pool_id arch) ~src dockerfile in
    Current.all (List.map build_arch archs)

  let name info = Cluster_api.Docker.Image_id.to_string info.hub_id

  let no_schedule = Current_cache.Schedule.v ()

  let pull_and_serve (module D : Current_docker.S.DOCKER) ~name op repo_id =
    let image =
      Current.component "pull" |>
      let> repo_id = repo_id in
      Current_docker.Raw.pull repo_id
      ~docker_context:D.docker_context
      ~schedule:no_schedule
      |> Current.Primitive.map_result (Result.map (fun raw_image ->
          D.Image.of_hash (Current_docker.Raw.Image.hash raw_image)
        ))
    in
    match op with
    | `Service -> D.service ~name ~image ()
    | `Compose contents ->
        let contents = Current.map (fun image ->
          Caddy.replace_hash_var ~hash:(D.Image.hash image) contents) image in
        D.compose ~name ~contents ()

  let deploy { sched; dockerfile; options; archs } { hub_id; services } src =
    let src = Current.map (fun x -> [x]) src in
    let target_label = Cluster_api.Docker.Image_id.repo hub_id |> String.map (function '/' | ':' -> '-' | c -> c) in
    let build_arch arch =
      let pool = pool_id arch in
      let tag = Printf.sprintf "live-%s-%s" target_label pool in
      let push_target = Cluster_api.Docker.Image_id.v ~repo:push_repo ~tag in
      Current_ocluster.build_and_push sched ~options ~push_target ~pool ~src dockerfile
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
        |> List.map (function
            (* | `Ci3 name -> pull_and_serve (module Ci3_docker) ~name `Service multi_hash *)
            (* | `Ci4 name -> pull_and_serve (module Ci4_docker) ~name `Service multi_hash *)
            (* | `Ci6 name -> pull_and_serve (module Ci6_docker) ~name `Service multi_hash *)
            (* | `Toxis name -> pull_and_serve (module Toxis_docker) ~name `Service multi_hash *)
            (* | `Tezos name -> pull_and_serve (module Tezos_docker) ~name `Service multi_hash *)
            (* | `Cb name -> pull_and_serve (module Cb_docker) ~name `Service multi_hash *)
            | `V3ocamlorg_cl name -> pull_and_serve (module V3ocamlorg_docker) ~name `Service multi_hash
            | `Ocamlorg_deployer name -> pull_and_serve (module Deploycamlorg_docker) ~name `Service multi_hash
            | `Ocamlorg_sw domains ->
              let name = Cluster_api.Docker.Image_id.tag hub_id in
              let contents = Caddy.compose {Caddy.name; domains} in
              pull_and_serve (module Ocamlorg_docker) ~name (`Compose contents) multi_hash
          )
        |> Current.all
end
module Cluster_build = Build.Make(Cluster)

(* [web_ui collapse_value] is a URL back to the deployment service, for links
   in status messages. *)
let web_ui =
  let base = Uri.of_string "https://deploy.ci.ocamllabs.io/" in
  fun repo -> Uri.with_query' base ["repo", repo]

let docker ?(archs=[`Linux_x86_64]) ?(options=Cluster_api.Docker.Spec.defaults) ~sched dockerfile targets =
  let build_info = { Cluster.sched; dockerfile = `Path dockerfile; options; archs } in
  let deploys =
    targets
    |> List.map (fun (branch, target, services) ->
        branch, { Cluster.
                  hub_id = Cluster_api.Docker.Image_id.of_string target |> or_fail;
                  services
                }
      )
  in
  (build_info, deploys)

let filter_list filter items =
  match filter with
  | None -> items
  | Some filter ->
    let items =
      items |> List.filter @@ fun (org, name, _) ->
      filter { Current_github.Repo_id.owner = Build.account org; name }
    in
    if items = [] then Fmt.failwith "No repository matches the filter!"
    else items

(* This is a list of GitHub repositories to monitor.
   For each one, it lists the builds that are made from that repository.
   For each build, it says which which branch gives the desired live version of
   the service, and where to deloy it. *)
let v ?app ?notify:channel ?filter ~sched ~staging_auth () =
  let ocurrent = Build.org ?app ~account:"ocurrent" 23342906 in
  let ocaml = Build.org ?app ~account:"ocaml" 18513252 in
  let build (org, name, builds) = Cluster_build.repo ?channel ~web_ui ~org ~name builds in
  let sched = Current_ocluster.v ~timeout ?push_auth:staging_auth sched in
  let docker = docker ~sched in
  Current.all @@ List.map build @@ filter_list filter [
    ocurrent, "ocurrent-deployer", [
        docker "Dockerfile"     ["live-ocaml-org", "ocurrent/ci.ocamllabs.io-deployer:live-ocaml-org", [`Ocamlorg_deployer "infra_deployer"]];
    ];
    ocaml, "v2.ocaml.org", [
      docker "Dockerfile.deploy"  ["master", "ocurrent/ocaml.org:live", [`Ocamlorg_sw ["v2.ocaml.org", "51.159.152.205"]]]
        ~options:include_git;
    ];
  ]
