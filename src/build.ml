open Current.Syntax

module Github = Current_github

type org = string * Current_github.Api.t

let org ~app ~account id =
  let api =
    Current_github.App.installation app ~account id
    |> Current_github.Installation.api
  in
  account, api

let head_of ~github repo name = Github.Api.head_of github repo (`Ref ("refs/heads/" ^ name))

(* Push a Slack notification to [channel] to say that [x] is updating [service] to [commit].
   [repo] is used for the URL in the message. *)
let notify ~channel ~web_ui ~service ~commit ~repo x =
  let s =
    let+ state = Current.state x
    and+ commit = commit in
    let uri = Github.Api.Commit.uri commit in
    Fmt.strf "@[<h>Deploy <%a|%a> as %s: <%s|%a>@]"
      Uri.pp uri Github.Api.Commit.pp commit
      service
      (Uri.to_string (web_ui repo)) (Current_term.Output.pp Current.Unit.pp) state
  in
  Current.all [
    Current_slack.post channel ~key:("deploy-" ^ service) s;
    x   (* If [x] fails, the whole pipeline should fail too. *)
  ]

let label l x =
  Current.component "%s" l |>
  let> x = x in
  Current.Primitive.const x

module Make(T : S.T) = struct
  let status_of_build ~url b =
    let+ state = Current.state b in
    match state with
    | Ok _              -> Github.Api.Status.v ~url `Success ~description:"Passed"
    | Error (`Active _) -> Github.Api.Status.v ~url `Pending
    | Error (`Msg m)    -> Github.Api.Status.v ~url `Failure ~description:m

  let repo ~channel ~web_ui ~org:(org, github) ~name build_specs =
    let repo_name = Printf.sprintf "%s/%s" org name in
    let repo = { Github.Repo_id.owner = org; name } in
    let root = Current.return ~label:repo_name () in      (* Group by repo in the diagram *)
    Current.with_context root @@ fun () ->
    let builds =
      let refs = Github.Api.ci_refs github repo in
      let collapse_value = repo_name ^ "-builds" in
      let url = web_ui collapse_value in
      let pipeline =
        refs
        |> Current.list_iter (module Github.Api.Commit) @@ fun commit ->
        let src = Current.map Github.Api.Commit.id commit in
        Current.all (
          build_specs |> List.map (fun (build_info, _deploys) -> T.build build_info src |> Current.ignore_value)
        )
        |> status_of_build ~url
        |> Github.Api.Commit.set_status commit "deployability"
      in
      Current.collapse
        ~key:"repo" ~value:collapse_value
        ~input:refs pipeline
    and deployments =
      let root = label "deployments" root in
      Current.with_context root @@ fun () ->
      Current.all (
        build_specs |> List.map (fun (build_info, deploys) ->
            Current.all (
              deploys |> List.map (fun (branch, deploy_info) ->
                  let service = T.name deploy_info in
                  let commit = head_of ~github repo branch in
                  let src = Current.map Github.Api.Commit.id commit in
                  let notify_repo = Printf.sprintf "%s-%s-%s" repo_name service branch in
                  T.deploy build_info deploy_info src
                  |> notify ~channel ~web_ui ~service ~commit ~repo:notify_repo
                )
            )
          )
      )
      |> Current.collapse
        ~key:"repo" ~value:repo_name
        ~input:root
    in
    Current.all [builds; deployments]
end
