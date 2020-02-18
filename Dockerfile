FROM ocurrent/opam:debian-10-ocaml-4.08 AS build
RUN sudo apt-get update && sudo apt-get install libev-dev m4 pkg-config libsqlite3-dev libgmp-dev -y --no-install-recommends
COPY --chown=opam \
	ocurrent/current.opam \
	ocurrent/current_web.opam \
	ocurrent/current_ansi.opam \
	ocurrent/current_docker.opam \
	ocurrent/current_git.opam \
	ocurrent/current_github.opam \
	ocurrent/current_rpc.opam \
	/src/ocurrent/
WORKDIR /src
RUN opam pin -yn add ./ocurrent
COPY --chown=opam deployer.opam /src/
RUN opam pin -yn add .
RUN opam install -y --deps-only .
ADD --chown=opam . .
RUN opam config exec -- dune build ./_build/install/default/bin/ocurrent-deployer

FROM debian:10
RUN apt-get update && apt-get install libev4 curl gnupg2 dumb-init git graphviz libsqlite3-dev ca-certificates netbase -y --no-install-recommends
RUN curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add -
RUN echo 'deb [arch=amd64] https://download.docker.com/linux/debian buster stable' >> /etc/apt/sources.list
RUN apt-get update && apt-get install docker-ce -y --no-install-recommends
WORKDIR /var/lib/ocurrent
ENTRYPOINT ["dumb-init", "/usr/local/bin/ocurrent-deployer"]
COPY --from=build /src/_build/install/default/bin/ocurrent-deployer /usr/local/bin/
