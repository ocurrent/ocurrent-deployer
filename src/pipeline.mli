(* Different deployer pipelines. *)
module Flavour : sig
  type t = [ `OCaml   (* for deploy.ci.ocaml.org *)
           | `Tarides (* for deploy.ci3.ocamllabs.io *)
           | `Mirage ] (* for deploy.mirage.io *)

  val cmdliner : t Cmdliner.Term.t
end

val tarides :
  ?app:Current_github.App.t ->
  ?notify:Slack_channel.t list ->
  ?filter:(Current_github.Repo_id.t -> bool) ->
  sched:Current_ocluster.Connection.t ->
  staging_auth:(string * string) option ->
  unit -> unit Current.t

val ocaml_org :
  ?app:Current_github.App.t ->
  ?notify:Slack_channel.t list ->
  ?filter:(Current_github.Repo_id.t -> bool) ->
  sched:Current_ocluster.Connection.t ->
  staging_auth:(string * string) option ->
  unit -> unit Current.t

val mirage :
  ?app:Current_github.App.t ->
  ?notify:Slack_channel.t list ->
  sched:Current_ocluster.Connection.t ->
  staging_auth:(string * string) option ->
  unit -> unit Current.t
