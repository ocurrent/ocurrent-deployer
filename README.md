# ocurrent-skeleton

This repository is a minimal self-contained [OCurrent][] pipeline,
suitable for use as a starting point for building your own pipelines.

To download and build this project:

```bash
git clone https://github.com/ocurrent/ocurrent-skeleton.git
cd ocurrent-skeleton
opam depext -i dune current current_web current_git
dune exec -- example --help
```

To run the example pipeline, pass a Git directory to monitor.
The project's own directory will do, e.g.

```bash
dune exec -- example .
```

Then browse to <http://localhost:8080> to access the web interface.
The default pipeline just monitors the HEAD of the repository, but
doesn't do anything with it.

To customise for your own project:

- Edit `src/pipeline.ml` to do something more interesting.
- Edit `src/main.ml` to set the help text and change the command-line parsing.
- Edit `src/dune` and `dune-project` to add additional libraries.

The [OCurrent wiki][] contains documentation and examples.
In particular, you might like to start by reading about the
[example pipelines][] or how to [write your own plugins][writing-plugins].

# Licensing

This project is in the public domain.
See [UNLICENSE][] for details.

[OCurrent]: https://github.com/ocurrent/ocurrent
[docker-base-images]: https://github.com/ocurrent/docker-base-images
[ocaml-ci]: https://github.com/ocurrent/ocaml-ci/
[writing-plugins]: https://github.com/ocurrent/ocurrent/wiki/Writing-plugins
[example pipelines]: https://github.com/ocurrent/ocurrent/wiki/Example-pipelines
[OCurrent wiki]: https://github.com/ocurrent/ocurrent/wiki
[UNLICENSE]: ./UNLICENSE
