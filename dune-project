(lang dune 1.11)
(name deployer)

(generate_opam_files true)

(source (github ocurrent/ocurrent-deployer))
(authors "talex5@gmail.com")
(maintainers "talex5@gmail.com")

(package
 (name deployer)
 (synopsis "Deploy other pipelines")
 (depends
  current
  current_web
  current_git
  current_github
  current_docker
  current_slack
  ocluster-api
  capnp-rpc-unix
  fmt
  lwt
  cmdliner
  (ocaml (>= 4.08.0))))
