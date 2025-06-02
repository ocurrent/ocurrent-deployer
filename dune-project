(lang dune 3.3)
(name deployer)
(generate_opam_files true)
(formatting disabled)
(source (github ocurrent/ocurrent-deployer))
(authors "Thomas Leonard <talex5@gmail.com>" "Tim McGilchrist <timmcgil@gmail.com>" "Mark Elvers <mark.elvers@tunbury.org>" "Antonin Décimo <antonin@tarides.com>" "Anil Madhavapeddy <anil@recoil.org>" "Navin Keswani <navin@novemberkilo.com>" "Lucas Pluvinage <lucas@tarides.com>" "David Allsopp <david.allsopp@metastack.com>" "Alpha DIALLO <moyodiallo@gmail.com>" "Etienne MARAIS <etienne@maiste.fr>" "Gargi Sharma <gs051095@gmail.com>" "Hannes Mehnert <hannes@mehnert.org>" "Cuihtlauac ALVARADO <cuihtmlauac@tarides.com>" "Patrick Ferris <patrick@sirref.org>" "Puneeth Chaganti <punchagan@muse-amuse.in>")
(maintainers "Mark Elvers <mark.elvers@tunbury.org>")
(package
 (name deployer)
 (synopsis "Deploy other OCurrent pipelines and services")
 (depends
  (ocaml (>= 4.14))
  (current (>= 0.6.4))
  current_web
  current_git
  current_github
  (current_docker (>= 0.7.0))
  current_slack
  current_ssh
  ocluster-api
  (current_ocluster (>= 0.3.0))
  (prometheus-app (>= 1.2))
  capnp-rpc-unix
  fmt
  ppx_deriving_yojson
  ppx_deriving
  logs
  (lwt (>= 5.6.1))
  (cmdliner (>= 1.1.0))
  (alcotest (and (>= 1.0.0) :with-test))
  (alcotest-lwt (and (>= 1.0.1) :with-test))))
