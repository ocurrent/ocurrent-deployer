module type T = sig
  type build_info
  type deploy_info

  type opam_refs

  val build :
    build_info ->
    ?opam:opam_refs ->
    Current_git.Commit_id.t Current.t -> unit Current.t

  val name : deploy_info -> string
  (** A unique service name to use in the Slack notifications and URLs. *)

  val deploy :
    build_info ->
    deploy_info ->
    ?opam:opam_refs ->
    Current_git.Commit_id.t Current.t -> unit Current.t
end
