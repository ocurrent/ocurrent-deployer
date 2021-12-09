FROM ocaml/opam:debian-11-ocaml-4.13@sha256:94b834d15b0614d974de1317bcc181eaadc23f5c13f8d60be92a5c24ce3a7777 AS build
RUN sudo apt-get update && sudo apt-get install libffi-dev libev-dev m4 pkg-config libsqlite3-dev libgmp-dev libssl-dev capnproto graphviz -y --no-install-recommends
RUN cd ~/opam-repository && git pull origin -q master && git reset --hard 7b361ce572d98a700d2e0018cb6e9c72db9a3675 && opam update
COPY --chown=opam \
	ocurrent/current_docker.opam \
	ocurrent/current_github.opam \
	ocurrent/current_git.opam \
	ocurrent/current.opam \
	ocurrent/current_rpc.opam \
	ocurrent/current_slack.opam \
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
    opam pin add -yn current_web.dev "./ocurrent" && \
    opam pin add -yn ocluster-api.dev "./ocluster"
COPY --chown=opam deployer.opam /src/
RUN opam pin -yn add .
RUN opam install -y --deps-only .
ADD --chown=opam . .
RUN opam config exec -- dune build ./_build/install/default/bin/ocurrent-deployer

FROM debian:11
RUN apt-get update && apt-get install libffi-dev libev4 openssh-client curl gnupg2 dumb-init git graphviz libsqlite3-dev ca-certificates netbase rsync -y --no-install-recommends
RUN curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add -
RUN echo 'deb [arch=amd64] https://download.docker.com/linux/debian bullseye stable' >> /etc/apt/sources.list
RUN apt-get update && apt-get install docker-ce -y --no-install-recommends
RUN apt-get update && apt-get install python3-pip -y && pip3 install docker-compose --no-cache-dir
WORKDIR /var/lib/ocurrent
ENTRYPOINT ["dumb-init", "/usr/local/bin/ocurrent-deployer"]
COPY config/ssh /root/.ssh
COPY config/docker /root/.docker
RUN docker context use ocaml-www1 && docker context use default
COPY --from=build /src/_build/install/default/bin/ocurrent-deployer /usr/local/bin/
