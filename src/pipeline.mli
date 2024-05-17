(* Different deployer pipelines. *)
module Flavour : sig
  type t = [ `OCaml   (* for deploy.ci.ocaml.org *)
           | `Tarides (* for deploy.ci3.ocamllabs.io *)
           | `Mirage ] (* for deploy.mirage.io *)

  val cmdliner : t Cmdliner.Term.t
end

module Tarides : sig
  val services :
    ?app:Current_github.App.t ->
    sched:Current_ocluster.Connection.t ->
    staging_auth:(string * string) option ->
    unit ->
    Cluster.service_info list

  val v :
    ?app:Current_github.App.t ->
    ?notify:Current_slack.channel ->
    ?filter:(Current_github.Repo_id.t -> bool) ->
    sched:Current_ocluster.Connection.t ->
    staging_auth:(string * string) option ->
    unit -> unit Current.t
end

module Ocaml_org : sig
  val services :
    ?app:Current_github.App.t ->
    sched:Current_ocluster.Connection.t ->
    staging_auth:(string * string) option ->
    unit ->
    Cluster.service_info list

  val v :
    ?app:Current_github.App.t ->
    ?notify:Current_slack.channel ->
    ?filter:(Current_github.Repo_id.t -> bool) ->
    sched:Current_ocluster.Connection.t ->
    staging_auth:(string * string) option ->
    unit -> unit Current.t
end

module Mirage : sig
  val unikernel_services :
    ?app:Current_github.App.t ->
    unit ->
    Packet_unikernel.service_info list

  val docker_services :
    ?app:Current_github.App.t ->
    sched:Current_ocluster.Connection.t ->
    staging_auth:(string * string) option ->
    unit ->
    Cluster.service_info list

  val v :
    ?app:Current_github.App.t ->
    ?notify:Current_slack.channel ->
    sched:Current_ocluster.Connection.t ->
    staging_auth:(string * string) option ->
    unit -> unit Current.t
end
