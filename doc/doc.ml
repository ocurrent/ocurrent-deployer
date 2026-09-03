open Deployer

let is_deployment (t : Pipeline.deployment) =
  t.services <> [] || t.compose <> None

let has_deployments t =
  List.exists is_deployment t.Pipeline.targets

let show_archs archs =
  String.concat ", " @@ List.map Cluster.Arch.to_string archs

let show_github_link ~org ~name branch =
  Printf.sprintf "https://github.com/%s/%s/tree/%s" org name branch

let show_docker_hub_link tag =
  let url =
    match String.split_on_char ':' tag with
    | [] -> None
    | org_and_name :: _ ->
      Some (Printf.sprintf "https://hub.docker.com/r/%s" org_and_name)
  in
  match url with
  | None -> Printf.sprintf "`%s`" tag
  | Some url -> Printf.sprintf "[`%s`](%s)" tag url

let show_services services =
  services
  |> List.map (fun ({name; docker_context = _; uri} : Cluster.service) ->
      let uri = match uri with
        | None -> ""
        | Some uri -> Printf.sprintf (" @ <https://%s>") uri
      in
      Printf.sprintf "    - `%s`%s" name uri
    )
  |> String.concat "\n"

let show_compose ({compose_context; project_name; image_name; compose_path} : Cluster.compose) =
  let module D = (val compose_context : Current_docker.S.DOCKER) in
  let host = Option.value D.docker_context ~default:"default" in
  let path = Option.map Fpath.to_string compose_path |> Option.value ~default:"docker-compose.yml" in
  Printf.sprintf "  - compose project: `%s` on `%s` (`%s`, pinning `%s`)" project_name host path image_name

let show_deploys (t : Pipeline.deployment) =
  match t.services, t.compose with
  | [], None -> ""
  | services, None -> Printf.sprintf "  - services:\n%s\n" (show_services services)
  | [], Some compose -> Printf.sprintf "%s\n" (show_compose compose)
  | services, Some compose ->
    Printf.sprintf "  - services:\n%s\n%s\n" (show_services services) (show_compose compose)

let show_docker ~org ~name t =
  if not (has_deployments t) then []
  else
    let header =
      Printf.sprintf "- `%s` on arches: %s" t.dockerfile (show_archs t.archs)
    in
    let deployments =
      List.map
        (fun t ->
          Printf.sprintf
            "  - branch: [`%s`](%s)\n  - registered image: %s\n%s"
            t.Pipeline.branch
            (show_github_link ~org ~name t.branch)
            (show_docker_hub_link t.target)
            (show_deploys t))
        t.targets
    in
    header :: deployments

let show_service (org, name, dockers) =
  if not @@ List.exists has_deployments dockers then None
  else
    let org = Build.account org in
    let header = [ Printf.sprintf "### [%s/%s](https://github.com/%s/%s)\n" org name org name ] in
    let dockers =
      List.map (show_docker ~org ~name) dockers
      |> List.flatten
    in
    Some (String.concat "\n" (header @ dockers))

let () =
  Printf.printf "# Deployed CI services\n\n";
  Printf.printf "For a given service, the specified Dockerfile is pulled from the specified branch and built to produce an image, which is then pushed to Docker Hub with the specified tag.\n\n";
  let f label deployer_url services =
    Printf.printf "## %s\n<%s>\n\n" label (Uri.to_string deployer_url);
    List.filter_map show_service services
    |> List.iter (Printf.printf "%s\n\n")
  in
  f "Tarides services" Pipeline.Tarides.base_url @@ Pipeline.Tarides.services ();
  f "OCaml Org services" Pipeline.Ocaml_org.base_url @@ Pipeline.Ocaml_org.services ();
  f "Mirage Docker services" Pipeline.Mirage.base_url @@ Pipeline.Mirage.services ()
