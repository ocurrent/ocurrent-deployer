# syntax=docker/dockerfile:1
FROM ocaml/opam:debian-11-ocaml-4.14@sha256:31210ba244a27fc4ca0b3dc1fe55c7393017b9367811ad19006dd19065bfd65b AS build
RUN sudo apt-get update && sudo apt-get install libffi-dev libev-dev m4 pkg-config libsqlite3-dev libgmp-dev libssl-dev capnproto graphviz -y --no-install-recommends
RUN cd ~/opam-repository && git fetch -q origin master && git reset --hard ec44728f8aed95c8576d461d31c0f14e0cd3097b && opam update
COPY --chown=opam \
	ocurrent/current_docker.opam \
	ocurrent/current_github.opam \
	ocurrent/current_git.opam \
	ocurrent/current.opam \
	ocurrent/current_rpc.opam \
	ocurrent/current_slack.opam \
	ocurrent/current_ssh.opam \
	ocurrent/current_web.opam \
	/src/ocurrent/
COPY --chown=opam \
        ocluster/*.opam \
        /src/ocluster/
WORKDIR /src
RUN opam pin add -yn current_docker.dev "./ocurrent" && \
    opam pin add -yn current_github.dev "./ocurrent" && \
    opam pin add -yn current_git.dev "./ocurrent" && \
    opam pin add -yn current.dev "./ocurrent" && \
    opam pin add -yn current_rpc.dev "./ocurrent" && \
    opam pin add -yn current_slack.dev "./ocurrent" && \
    opam pin add -yn current_ssh.dev "./ocurrent" && \
    opam pin add -yn current_web.dev "./ocurrent" && \
    opam pin add -yn ocluster-api.dev "./ocluster"
COPY --chown=opam deployer.opam /src/
RUN opam pin -yn add .
RUN opam install -y --deps-only .
ADD --chown=opam . .
RUN opam config exec -- dune build ./_build/install/default/bin/ocurrent-deployer

FROM debian:11
RUN curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add -
RUN echo 'deb [arch=amd64] https://download.docker.com/linux/debian bullseye stable' >> /etc/apt/sources.list
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      libffi-dev libev4 openssh-client curl gnupg2 dumb-init git graphviz libsqlite3-dev ca-certificates netbase rsync awscli \
      docker-ce docker-ce-cli docker-compose-plugin && \
    rm -rf /var/lib/apt/lists/*
RUN curl -L https://raw.githubusercontent.com/docker/compose-cli/main/scripts/install/install_linux.sh | sh
WORKDIR /var/lib/ocurrent
ENTRYPOINT ["dumb-init", "/usr/local/bin/ocurrent-deployer"]
COPY config/ssh /root/.ssh
COPY config/docker /root/.docker
RUN docker context use default
COPY --link --from=build /src/_build/install/default/bin/ocurrent-deployer /usr/local/bin/
