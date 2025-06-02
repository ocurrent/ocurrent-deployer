# syntax=docker/dockerfile:1
FROM ocaml/opam:debian-12-ocaml-4.14 AS build
RUN sudo ln -sf /usr/bin/opam-2.3 /usr/bin/opam && opam init --reinit -ni
RUN opam option --global 'archive-mirrors+="https://opam.ocaml.org/cache"'
RUN sudo rm -f /etc/apt/apt.conf.d/docker-clean; echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' | sudo tee /etc/apt/apt.conf.d/keep-cache
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    sudo apt update && sudo apt-get --no-install-recommends install -y \
    capnproto \
    graphviz \
    libev-dev \
    libffi-dev \
    libgmp-dev \
    libsqlite3-dev \
    libssl-dev \
    m4 \
    pkg-config
RUN cd ~/opam-repository && git fetch -q origin master && git reset --hard a4ff4b0b6803cb31deb09240efdad753f95d0058 && opam update
COPY --chown=opam --link deployer.opam /src/
# WORKDIR must be after COPY to avoid perms problems
WORKDIR /src
RUN opam pin -yn add .
RUN --mount=type=cache,target=/home/opam/.opam/download-cache,sharing=locked,uid=1000,gid=1000 \
    opam install -y --deps-only .
ADD --chown=opam . .
RUN opam exec -- dune build ./_build/install/default/bin/ocurrent-deployer

FROM debian:12
RUN rm -f /etc/apt/apt.conf.d/docker-clean; echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt update && apt-get --no-install-recommends install -y \
    awscli \
    ca-certificates \
    curl \
    dumb-init \
    git \
    gnupg2 \
    graphviz \
    libev4 \
    libsqlite3-dev \
    netbase \
    openssh-client \
    rsync \
    libffi-dev
RUN curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add -
RUN echo 'deb https://download.docker.com/linux/debian bookworm stable' >> /etc/apt/sources.list
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt update && apt-get --no-install-recommends install -y \
    docker-buildx-plugin \
    docker-ce \
    docker-ce-cli \
    docker-compose-plugin
WORKDIR /var/lib/ocurrent
ENTRYPOINT ["dumb-init", "/usr/local/bin/ocurrent-deployer"]
COPY --link create-config.sh .
RUN ./create-config.sh
RUN docker context use default
COPY --from=build --link /src/_build/install/default/bin/ocurrent-deployer /usr/local/bin/
