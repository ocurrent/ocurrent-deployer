(* TODO: This sould not live in the pipeline *)
(* Different deployer pipelines. *)
module Flavour : sig
  type t = [ `OCaml   (* for deploy.ci.ocaml.org *)
           | `Tarides (* for deploy.ci3.ocamllabs.io *)
           | `Mirage ] (* for deploy.mirage.io *)

  val to_string : t -> string
  val cmdliner : t Cmdliner.Term.t
end

type deployment = {
  branch : string;
  target : string;
  services : Cluster.service list;
}

type docker = {
  dockerfile : string;
  targets : deployment list;
  archs : Cluster.Arch.t list;
  options : Cluster_api.Docker.Spec.options;
}

type service = Build.org * string * docker list

module type Constellation = sig
  (** The interface for a pipelines that can be deployed *)

  val services : ?app:Current_github.App.t -> unit -> service list

  val admins : string list

  val v :
    ?app:Current_github.App.t ->
    ?notify:Current_slack.channel ->
    ?filter:(Current_github.Repo_id.t -> bool) ->
    sched:Current_ocluster.Connection.t ->
    staging_auth:(string * string) option ->
    unit -> unit Current.t
end

module Tarides : Constellation
module Ocaml_org : Constellation
module Mirage : Constellation
