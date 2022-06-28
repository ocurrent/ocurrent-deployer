let src = Logs.Src.create "deployer.index" ~doc:"deployer indexer"
module Log = (val Logs.src_log src : Logs.LOG)

module Db = Current.Db

module Job_map = Astring.String.Map

type t = {
  db : Sqlite3.db;
  record_job : Sqlite3.stmt;
  remove : Sqlite3.stmt;
  get_jobs : Sqlite3.stmt;
  get_job : Sqlite3.stmt;
  get_job_ids : Sqlite3.stmt;
  full_hash : Sqlite3.stmt;
}

let or_fail label x =
  match x with
  | Sqlite3.Rc.OK -> ()
  | err -> Fmt.failwith "Sqlite3 %s error: %s" label (Sqlite3.Rc.to_string err)

let db = lazy (
  let db = Lazy.force Current.Db.v in
  Current_cache.Db.init ();
  Sqlite3.exec db {|
CREATE TABLE IF NOT EXISTS deployer_index (
  owner     TEXT NOT NULL,
  name      TEXT NOT NULL,
  hash      TEXT NOT NULL,
  variant   TEXT NOT NULL,
  job_id    TEXT,
  PRIMARY KEY (owner, name, hash, variant)
)|} |> or_fail "create table";
  let record_job = Sqlite3.prepare db "INSERT OR REPLACE INTO deployer_index \
                                     (owner, name, hash, variant, job_id) \
                                     VALUES (?, ?, ?, ?, ?)" in
  let remove = Sqlite3.prepare db "DELETE FROM deployer_index \
                                     WHERE owner = ? AND name = ? AND hash = ? AND variant = ?" in
  let get_jobs = Sqlite3.prepare db "SELECT deployer_index.variant, deployer_index.job_id, cache.ok, cache.outcome \
                                     FROM deployer_index \
                                     LEFT JOIN cache ON deployer_index.job_id = cache.job_id \
                                     WHERE deployer_index.owner = ? AND deployer_index.name = ? AND deployer_index.hash = ?" in
  let get_job = Sqlite3.prepare db "SELECT job_id FROM deployer_index \
                                     WHERE owner = ? AND name = ? AND hash = ? AND variant = ?" in
  let get_job_ids = Sqlite3.prepare db "SELECT variant, job_id FROM deployer_index \
                                     WHERE owner = ? AND name = ? AND hash = ?" in
  let full_hash = Sqlite3.prepare db "SELECT DISTINCT hash FROM deployer_index \
                                      WHERE owner = ? AND name = ? AND hash LIKE ?" in
      {
        db;
        record_job;
        remove;
        get_jobs;
        get_job;
        get_job_ids;
        full_hash
      }
)

let init () = ignore (Lazy.force db)

let get_job_ids_with_variant t ~owner ~name ~hash =
  Db.query t.get_job_ids Sqlite3.Data.[ TEXT owner; TEXT name; TEXT hash ]
  |> List.map @@ function
  | Sqlite3.Data.[ TEXT variant; NULL ] -> variant, None
  | Sqlite3.Data.[ TEXT variant; TEXT id ] -> variant, Some id
  | row -> Fmt.failwith "get_job_ids: invalid row %a" Db.dump_row row

let record ~repo ~hash jobs =
  let { Current_github.Repo_id.owner; name } = repo in
  let t = Lazy.force db in
  let jobs = Job_map.of_list jobs in
  let previous = get_job_ids_with_variant t ~owner ~name ~hash |> Job_map.of_list in
  let merge variant prev job =
    let set job_id =
      Log.info (fun f -> f "@[<h>Index.record %s/%s %s %s -> %a@]"
                   owner name (Astring.String.with_range ~len:6 hash) variant Fmt.(option ~none:(any "-") string) job_id);
      match job_id with
      | None -> Db.exec t.record_job Sqlite3.Data.[ TEXT owner; TEXT name; TEXT hash; TEXT variant; NULL ]
      | Some id -> Db.exec t.record_job Sqlite3.Data.[ TEXT owner; TEXT name; TEXT hash; TEXT variant; TEXT id ]
    in
    let update j1 j2 =
      match j1, j2 with
      | Some j1, Some j2 when j1 = j2 -> ()
      | None, None -> ()
      | _, j2 -> set j2
    in
    let remove () =
      Log.info (fun f -> f "@[<h>Index.record %s/%s %s %s REMOVED@]"
                   owner name (Astring.String.with_range ~len:6 hash) variant);
      Db.exec t.remove Sqlite3.Data.[ TEXT owner; TEXT name; TEXT hash; TEXT variant ]
    in
    begin match prev, job with
      | Some j1, Some j2 -> update j1 j2
      | None, Some j2 -> set j2
      | Some _, None -> remove ()
      | None, None -> assert false
    end;
    None
  in
  let _ : [`Empty] Job_map.t = Job_map.merge merge previous jobs in
  ()

let get_job_ids  ~owner ~name ~hash =
  let t = Lazy.force db in
  get_job_ids_with_variant t ~owner ~name ~hash |> List.filter_map snd