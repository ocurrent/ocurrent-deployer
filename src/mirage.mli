module Make(Docker : Current_docker.S.DOCKER) : sig
  val deploy : name:string -> ssh_host:string -> Docker.Image.t Current.t -> unit Current.t
  (** [deploy ~name ~ssh_host image] deploys [image] as the unikernel [name] on [ssh_host]. *)
end

val deploy_from_registry : name:string -> ssh_host:string -> string Current.t -> unit Current.t
(** [deploy_from_registry ~name ~ssh_host repo_id] extracts the unikernel from the
    registry image [repo_id] using crane and deploys it as [name] on [ssh_host]. *)
