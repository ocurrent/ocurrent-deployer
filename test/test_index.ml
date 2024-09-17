module Index = Deployer.Index

let test_simple () =
  let owner = "owner" in
  let name = "name" in
  let repo = { Current_github.Repo_id.owner; name } in
  let hash = "abc" in
  let _ = Lazy.force Current.Db.v in
  Index.init ();
  Index.record ~repo ~hash [ ("build", Some "job1"); ("deploy", None) ];
  Alcotest.(check (list string)) "Job-ids" ["job1"] @@ Index.get_job_ids ~owner ~name ~hash;
  Index.record ~repo ~hash [ ("build", Some "job2") ];
  Alcotest.(check (list string)) "Job-ids" ["job2"] @@ List.sort String.compare @@ Index.get_job_ids ~owner ~name ~hash

let test_access_role () =
  let case msg = Alcotest.(check' bool) ~msg in
  let admins = ["Kenta"; "Hai"; "Jakob"] in
  let has_role = Deployer.Access.user_has_role ~admins in
  case "unauthenticated users SHOULD have view and monitor role"
    ~expected:true
    ~actual:(List.for_all (has_role None) [`Viewer; `Monitor]);
  case "unauthenticated users MUST NOT have admin or builder role"
    ~expected:false
    ~actual:(List.for_all (has_role None) [`Admin; `Builder]);
  case "non-admin users MUST NOT have admin or builder role"
    ~expected:false
    ~actual:(has_role (Some "Auden") `Admin || has_role (Some "Wenjing") `Builder);
  case "admin users SHOULD have every role"
    ~expected:true
    ~actual:(List.for_all (has_role (Some "Kenta")) [`Viewer; `Monitor; `Builder; `Admin])


let tests = [
    Alcotest_lwt.test_case_sync "simple" `Quick test_simple;
    Alcotest_lwt.test_case_sync "access roles" `Quick test_access_role;
]
