val init : Fmt.style_renderer option -> Logs.level option -> unit
(** Initialise the Logs library with some sensible defaults. *)

val cmdliner : unit Cmdliner.Term.t
(** A Cmdliner term to initialise the Logs library. *)

val run : unit Current.or_error Lwt.t -> unit Current.or_error
(** [run x] is like [Lwt_main.run x], but logs the returned error, if any. *)
