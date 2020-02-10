(lang dune 1.11)
(name example)

(generate_opam_files true)

(package
 (name example)
 (synopsis "An OCurrent pipeline")
 (description "A longer description")
 (depends
  current
  current_web
  current_git
  fmt
  lwt
  cmdliner
  (ocaml (>= 4.08.0))))
