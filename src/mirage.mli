module Make(Docker : Current_docker.S.DOCKER) : sig
  val deploy : name:string -> ssh_host:string -> Docker.Image.t Current.t -> unit Current.t
  (** [deploy ~name ~ssh_host image] deploys [image] as the unikernel [name] on [ssh_host]. *)
end
