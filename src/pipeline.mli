(* Different deployer pipelines. *)
module Flavour : sig
  type t = [ `OCaml   (* for deploy.ci.ocaml.org *)
           | `Tarides (* for deploy.ci3.ocamllabs.io *)
           | `Toxis ] (* for deploy.ocamllabs.io *)

  val cmdliner : t Cmdliner.Term.t
end

val tarides :
  ?app:Current_github.App.t ->
  ?notify:Current_slack.channel ->
  ?filter:(Current_github.Repo_id.t -> bool) ->
  sched:Current_ocluster.Connection.t ->
  staging_auth:(string * string) option ->
  unit -> unit Current.t

val ocaml_org :
  ?app:Current_github.App.t ->
  ?notify:Current_slack.channel ->
  ?filter:(Current_github.Repo_id.t -> bool) ->
  sched:Current_ocluster.Connection.t ->
  staging_auth:(string * string) option ->
  unit -> unit Current.t

val toxis :
  ?app:Current_github.App.t ->
  ?notify:Current_slack.channel ->
  unit -> unit Current.t