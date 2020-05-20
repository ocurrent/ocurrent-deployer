module type T = sig
  type build_info
  type binary
  type deploy_info

  val build :
    build_info ->
    Current_git.Commit.t Current.t -> binary Current.t

  val name : deploy_info -> string
  (** A unique service name to use in the Slack notifications and URLs. *)

  val deploy :
    deploy_info ->
    binary Current.t -> unit Current.t
end
