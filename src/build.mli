type org

val org :
  ?app:Current_github.App.t ->
  account:string -> int -> org
(** [org ~app account installation] look up a GitHub organisation by ID.
    [installation] is ignored if [app] is [None].
    @param app is used to set the status, if present *)

val account : org -> string

val api : org -> Current_github.Api.t option

module Make(T : S.T) : sig
  val repo :
    ?channel:Current_slack.channel ->
    web_ui:(string -> Uri.t) ->
    org:org ->
    ?additional_build_args:string list Current.t ->
    name:string ->
    (T.build_info * (string * T.deploy_info) list) list ->
    unit Current.t
    (** [repo ~channel ~web_ui ~org ~name builds] is an OCurrent pipeline to
        handle all builds and deployments under [org/name]. Each build
        is a [(build_info, [branch, deploy_info])] pair.
        It builds every branch and PR using [T.build], and deploys the
        given branches using [T.deploy], sending notifications to [channel].
        If [org] does not have an app then (for local testing) it only builds the deployment branches.
    *)
end
