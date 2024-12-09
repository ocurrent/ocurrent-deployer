FROM ocaml/opam:debian-12-ocaml-4.14@sha256:06d58a5cb1ab7875e8d94848102be43f6492e95320e8e9a9ecb9167654d0ee3f AS build
RUN sudo apt-get update && sudo apt-get install libffi-dev libev-dev m4 pkg-config libsqlite3-dev libgmp-dev libssl-dev capnproto graphviz -y --no-install-recommends
RUN cd ~/opam-repository && git fetch -q origin master && git reset --hard 99bc90ff813af4d02cb0627f6b3e5a8c84e2e04a && opam update
COPY --chown=opam deployer.opam /src/
# WORKDIR must be after COPY to avoid perms problems
WORKDIR /src
RUN opam pin -yn add .
RUN opam install -y --deps-only .
ADD --chown=opam . .
RUN opam config exec -- dune build ./_build/install/default/bin/ocurrent-deployer

FROM debian:12
RUN apt-get update && apt-get install libffi-dev libev4 openssh-client curl gnupg2 dumb-init git graphviz libsqlite3-dev ca-certificates netbase rsync awscli -y --no-install-recommends
RUN curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add -
RUN echo 'deb [arch=amd64] https://download.docker.com/linux/debian bookworm stable' >> /etc/apt/sources.list
RUN apt-get update && apt-get install docker-ce docker-ce-cli docker-buildx-plugin docker-compose-plugin -y --no-install-recommends
WORKDIR /var/lib/ocurrent
ENTRYPOINT ["dumb-init", "/usr/local/bin/ocurrent-deployer"]
COPY create-config.sh create-config.sh
RUN ./create-config.sh
RUN docker context use default
COPY --from=build /src/_build/install/default/bin/ocurrent-deployer /usr/local/bin/
