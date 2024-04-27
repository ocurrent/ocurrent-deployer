open Current.Syntax

module Github = Current_github

type org = string * Current_github.Api.t option

let account = fst
let api = snd

let org ?app ~account id =
  let api =
    app |> Option.map @@ fun app ->
    Current_github.App.installation app ~account id
    |> Current_github.Installation.api
  in
  account, api

let head_of ?github repo name =
  let gref = `Ref ("refs/heads/" ^ name) in
  match github with
  | None ->
    None, Github.Api.Anonymous.head_of repo gref
  | Some github ->
    let commit = Github.Api.head_of github repo gref in
    Some commit, Current.map Github.Api.Commit.id commit

(* Push a Slack notification to [channel] to say that [x] is updating [service] to [commit].
   [repo] is used for the URL in the message. *)
let notify ?channel ~web_ui ~service ~commit ~repo x =
  match channel with
  | None -> x
  | Some { Slack_channel.uri; mode; repositories = _ } ->
    let s =
      let+ state = Current.state ~hidden:true x
      and+ commit in
      match state, mode with
      | Error (`Msg _), Slack_channel.Failure
      | _, Slack_channel.All -> (
          let uri = Github.Api.Commit.uri commit in
          let s = Fmt.str "@[<h>Deploy <%a|%a> as %s: <%s|%a>@]"
            Uri.pp uri Github.Api.Commit.pp_short commit
            service
            (Uri.to_string (web_ui repo)) (Current_term.Output.pp Current.Unit.pp) state
          in
          Some s)
      | _ -> None
    in
    Current.(option_iter
      (fun s -> all [
          Current_slack.post uri ~key:("deploy-" ^ service) s;
          x (* If [x] fails, the whole pipeline should fail too. *)
        ]
      )) s

let label l x =
  Current.component "%s" l |>
  let> x in
  Current.Primitive.const x

module Make(T : S.T) = struct
  (* TODO Summarise build results. *)
  let status_of_build ~url build =
    let+ state = Current.state build in
    match state with
    | Ok _              -> Github.Api.CheckRunStatus.v ~url (`Completed `Success) ~summary:"Passed"
    | Error (`Active _) -> Github.Api.CheckRunStatus.v ~url `Queued
    | Error (`Msg m)    -> Github.Api.CheckRunStatus.v ~url (`Completed (`Failure m)) ~summary:m

  let send_slack_message ~web_ui ~service ~commit ~repo_name deploy channels =
    let f channel =
      match channel.Slack_channel.repositories with
      | All_repos -> notify ~channel ~web_ui ~service ~commit ~repo:repo_name deploy
      | Some_repos repositories ->
        if List.exists (String.equal repo_name) repositories then
          notify ~channel ~web_ui ~service ~commit ~repo:repo_name deploy
        else
          deploy
    in
    List.map f channels

  let repo ?channels ~web_ui ~org:(org, github) ?additional_build_args ~name build_specs =
    let repo_name = Printf.sprintf "%s/%s" org name in
    let repo = { Github.Repo_id.owner = org; name } in
    let root = Current.return ~label:repo_name () in      (* Group by repo in the diagram *)
    Current.with_context root @@ fun () ->
    let builds = github |> Option.map @@ fun github ->
      let refs = Github.Api.ci_refs github repo in
      let collapse_value = repo_name ^ "-builds" in
      let url = web_ui collapse_value in
      let pipeline =
        refs
        |> Current.list_iter (module Github.Api.Commit) @@ fun commit ->
        let src = Current.map Github.Api.Commit.id commit in
        Current.all (
          List.map (fun (build_info, _) ->
              T.build ?additional_build_args build_info repo src
            ) build_specs
        )
        |> status_of_build ~url
        |> Github.Api.CheckRun.set_status commit "deployability"
      in
      Current.collapse ~key:"repo" ~value:collapse_value ~input:refs pipeline
    and deployment =
      let root = label "deployments" root in
      Current.with_context root @@ fun () ->
      Current.all (
        build_specs |> List.map (fun (build_info, deploys) ->
          Current.all (
            deploys |> List.map (fun (branch, deploy_info) ->
              let service = T.name deploy_info in
              let commit, src = head_of ?github repo branch in
              let deploy = T.deploy build_info deploy_info ?additional_build_args src in
              match channels, commit with
              | Some channels, Some commit ->
                  send_slack_message ~web_ui ~service ~commit ~repo_name deploy channels
              | _ -> [ deploy ]
            ) |> List.flatten
          )
        )
      ) |> Current.collapse ~key:"repo" ~value:repo_name ~input:root
    in
    Current.all (deployment :: Option.to_list builds)
end
