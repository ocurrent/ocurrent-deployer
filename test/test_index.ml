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

let tests = [
    Alcotest_lwt.test_case_sync "simple" `Quick test_simple;
]

