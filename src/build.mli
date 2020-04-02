type org

val org :
  app:Current_github.App.t ->
  account:string -> int -> org
(** Look up a GitHub organisation by ID. *)

val repo :
  web_ui:(string -> Uri.t) ->
  build:(dockerfile:string ->
         src:Current_git.Commit.t Current.t ->
         [`Docker | `Unikernel] ->
         unit Current.t) ->
  deploy:(dockerfile:string ->
          src:Current_git.Commit.t Current.t ->
          commit:Current_github.Api.Commit.t Current.t ->
          collapse_value:string ->
          ([`Docker of _ | `Unikernel of _ ] as 'a) -> unit Current.t) ->
  org:org ->
  name:string ->
  (string * string * 'a) list ->
  unit Current.t
(** [repo ~web_ui ~build ~deploy ~org ~name builds] is an OCurrent pipeline to
    handle all builds and deployments under [org/name].
    @param build Sub-pipeline used to build and test every branch and PR.
    @param deploy Sub-pipeline used to deploy each specified deployment branch.
    @param builds A list of (dockerfile, live-branch, target) tuples
                  (e.g. ["Dockerfile.web", "live-web", `Docker ...]). *)
