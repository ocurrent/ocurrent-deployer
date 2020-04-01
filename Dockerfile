# syntax=docker/dockerfile:experimental@sha256:787107d7f7953cb2d95ee81cc7332d79aca9328129318e08fc7ffbd252a20656
FROM ocurrent/opam:debian-10-ocaml-4.08 AS build
RUN sudo apt-get update && sudo apt-get install libev-dev m4 pkg-config libsqlite3-dev libgmp-dev -y --no-install-recommends
COPY --chown=opam \
	ocurrent/current_ansi.opam \
	ocurrent/current_docker.opam \
	ocurrent/current_github.opam \
	ocurrent/current_git.opam \
	ocurrent/current_incr.opam \
	ocurrent/current.opam \
	ocurrent/current_rpc.opam \
	ocurrent/current_slack.opam \
	ocurrent/current_web.opam \
	/src/ocurrent/
WORKDIR /src
RUN opam pin add -yn current_ansi.dev "./ocurrent" && \
    opam pin add -yn current_docker.dev "./ocurrent" && \
    opam pin add -yn current_github.dev "./ocurrent" && \
    opam pin add -yn current_git.dev "./ocurrent" && \
    opam pin add -yn current_incr.dev "./ocurrent" && \
    opam pin add -yn current.dev "./ocurrent" && \
    opam pin add -yn current_rpc.dev "./ocurrent" && \
    opam pin add -yn current_slack.dev "./ocurrent" && \
    opam pin add -yn current_web.dev "./ocurrent"
COPY --chown=opam deployer.opam /src/
RUN opam pin -yn add .
RUN --mount=type=cache,target=/home/opam/.opam/download-cache,uid=1000 opam install -y --deps-only .
ADD --chown=opam . .
RUN opam config exec -- dune build ./_build/install/default/bin/ocurrent-deployer

FROM debian:10
RUN apt-get update && apt-get install libev4 openssh-client curl gnupg2 dumb-init git graphviz libsqlite3-dev ca-certificates netbase -y --no-install-recommends
RUN curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add -
RUN echo 'deb [arch=amd64] https://download.docker.com/linux/debian buster stable' >> /etc/apt/sources.list
RUN apt-get update && apt-get install docker-ce -y --no-install-recommends
WORKDIR /var/lib/ocurrent
ENTRYPOINT ["dumb-init", "/usr/local/bin/ocurrent-deployer"]
COPY config/ssh /root/.ssh
COPY config/docker /root/.docker
COPY --from=build /src/_build/install/default/bin/ocurrent-deployer /usr/local/bin/
