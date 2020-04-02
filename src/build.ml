open Current.Syntax

module Git = Current_git
module Github = Current_github

type org = string * Current_github.Api.t

let org ~app ~account id =
  let api =
    Current_github.App.installation app ~account id
    |> Current_github.Installation.api
  in
  account, api

let head_of ~github repo name = Github.Api.head_of github repo (`Ref ("refs/heads/" ^ name))

(* Strip deployment information and remove duplicates. *)
let ignore_branch items =
  items
  |> List.map (function
      | (d, _, `Docker _) -> d, `Docker
      | (d, _, `Unikernel _) -> d, `Unikernel
    )
  |> List.sort_uniq compare

let status_of_build ~url b =
  let+ state = Current.state b in
  match state with
  | Ok _              -> Github.Api.Status.v ~url `Success ~description:"Passed"
  | Error (`Active _) -> Github.Api.Status.v ~url `Pending
  | Error (`Msg m)    -> Github.Api.Status.v ~url `Failure ~description:m

let repo ~web_ui ~build ~deploy ~org:(org, github) ~name builds =
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
      let src = Git.fetch (Current.map Github.Api.Commit.id commit) in
      Current.all (
        ignore_branch builds |> List.map (fun (dockerfile, target) -> build ~dockerfile ~src target)
      )
      |> status_of_build ~url
      |> Github.Api.Commit.set_status commit "deployability"
    in
    Current.collapse
      ~key:"repo" ~value:collapse_value
      ~input:refs pipeline
  and deployments =
    Current.all (
      builds |> List.map (fun (dockerfile, branch, target) ->
          let commit = head_of ~github repo branch in
          let src = Git.fetch (Current.map Github.Api.Commit.id commit) in
          let collapse_value = Printf.sprintf "%s-%s-%s" repo_name dockerfile branch in
          let build = deploy ~dockerfile ~src ~commit ~collapse_value target in
          Current.collapse
            ~key:"repo" ~value:collapse_value
            ~input:commit build
        )
    )
  in
  Current.all [builds; deployments]
