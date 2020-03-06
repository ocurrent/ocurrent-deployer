module Make(Docker : Current_docker.S.DOCKER) : sig
  type t

  val config : ssh_host:string -> unit -> t
  (** [config ~ssh_host ()] is a configuration which deploys to
      [ssh_host], which must be the same host as [Docker]. *)

  val deploy : t -> name:string -> Docker.Image.t Current.t -> unit Current.t
  (** [deploy t ~name image] deploys [image] as the unikernel [name]. *)
end
