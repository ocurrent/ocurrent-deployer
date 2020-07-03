module type T = sig
  type build_info
  type deploy_info

  val build :
    build_info ->
    Current_git.Commit.t Current.t -> unit Current.t

  val name : deploy_info -> string
  (** A unique service name to use in the Slack notifications and URLs. *)

  val deploy :
    build_info ->
    deploy_info ->
    Current_git.Commit.t Current.t -> unit Current.t
end
