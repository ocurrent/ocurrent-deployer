open Deployer

let has_deployments t =
  List.exists
    (fun t -> t.Pipeline.services != [])
    t.Pipeline.targets

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
            "  - branch [`%s`](%s) built at %s"
            t.Pipeline.branch
            (show_github_link ~org ~name t.branch)
            (show_docker_hub_link t.target))
        t.targets
    in
    header :: deployments

let show_service (org, name, dockers) =
  if not @@ List.exists has_deployments dockers then None
  else
    let org = Build.account org in
    let header = [ Printf.sprintf "### [%s/%s](https://github.com/%s/%s)" org name org name ] in
    let dockers =
      List.map (show_docker ~org ~name) dockers
      |> List.flatten
    in
    Some (String.concat "\n" (header @ dockers))

let () =
  Printf.printf "# Deployed CI services\n\n";
  Printf.printf "For a given service, the specified Dockerfile is pulled from the specified branch and built to produce an image, which is then pushed to Docker Hub with the specified tag.\n\n";
  let f label services =
    Printf.printf "## %s\n\n" label;
    List.filter_map show_service services
    |> List.iter (Printf.printf "%s\n\n")
  in
  f "Tarides services" @@ Pipeline.Tarides.services ();
  f "OCaml Org services" @@ Pipeline.Ocaml_org.services ();
  f "Mirage Docker services" @@ Pipeline.Mirage.services ()
