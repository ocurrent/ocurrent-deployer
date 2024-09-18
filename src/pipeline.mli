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

type pipeline =
  ?app:Current_github.App.t ->
  ?notify:Current_slack.channel ->
  ?filter:(Current_github.Repo_id.t -> bool) ->
  sched:Current_ocluster.Connection.t ->
  staging_auth:(string * string) option ->
  unit ->
  unit Current.t
(** A pipeline deploying a set of services *)

type deployer =
  { pipeline: pipeline
  (** A pipeline to deploy a set of {!service}. *)
  ; admins: string list
  (** The administrators for the deployer admins.*)
  }

module type Deployer = sig
  (** A definition of a {!type:deployer}. *)

  val services : ?app:Current_github.App.t -> unit -> service list
  (** The list of services deployed *)
end

module Tarides : Deployer
(** Implementation of the deployer for Tarides services. *)

module Ocaml_org : Deployer
(** Implementation of the deployer for ocaml.org services. *)

module Mirage : Deployer
(** Implementation of the deployer for Mirage services. *)


val cmdliner : deployer Cmdliner.Term.t
(** [cmdliner] is a Cmdliner term that selects a {!type:deployer} pipelines
    along with the list of admins for the selected pipeline *)
