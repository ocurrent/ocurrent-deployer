# Deployed CI services

For a given service, the specified Dockerfile is pulled from the specified branch and built to produce an image, which is then pushed to Docker Hub with the specified tag.

## Tarides services

### [ocurrent/ocurrent-deployer](https://github.com/ocurrent/ocurrent-deployer)
- `Dockerfile` on arches: x86_64
  - branch [`live-ci3`](https://github.com/ocurrent/ocurrent-deployer/tree/live-ci3) built at [`ocurrent/ci.ocamllabs.io-deployer:live-ci3`](https://hub.docker.com/r/ocurrent/ci.ocamllabs.io-deployer)

### [ocurrent/ocaml-ci](https://github.com/ocurrent/ocaml-ci)
- `Dockerfile` on arches: x86_64, arm64
  - branch [`live-engine`](https://github.com/ocurrent/ocaml-ci/tree/live-engine) built at [`ocurrent/ocaml-ci-service:live`](https://hub.docker.com/r/ocurrent/ocaml-ci-service)
- `Dockerfile.gitlab` on arches: x86_64, arm64
  - branch [`live-engine`](https://github.com/ocurrent/ocaml-ci/tree/live-engine) built at [`ocurrent/ocaml-ci-gitlab-service:live`](https://hub.docker.com/r/ocurrent/ocaml-ci-gitlab-service)
- `Dockerfile.web` on arches: x86_64, arm64
  - branch [`live-www`](https://github.com/ocurrent/ocaml-ci/tree/live-www) built at [`ocurrent/ocaml-ci-web:live`](https://hub.docker.com/r/ocurrent/ocaml-ci-web)
  - branch [`staging-www`](https://github.com/ocurrent/ocaml-ci/tree/staging-www) built at [`ocurrent/ocaml-ci-web:staging`](https://hub.docker.com/r/ocurrent/ocaml-ci-web)

### [ocurrent/ocaml-multicore-ci](https://github.com/ocurrent/ocaml-multicore-ci)
- `Dockerfile` on arches: x86_64
  - branch [`live`](https://github.com/ocurrent/ocaml-multicore-ci/tree/live) built at [`ocurrent/multicore-ci:live`](https://hub.docker.com/r/ocurrent/multicore-ci)
- `Dockerfile.web` on arches: x86_64
  - branch [`live-web`](https://github.com/ocurrent/ocaml-multicore-ci/tree/live-web) built at [`ocurrent/multicore-ci-web:live`](https://hub.docker.com/r/ocurrent/multicore-ci-web)

### [ocurrent/ocurrent.org](https://github.com/ocurrent/ocurrent.org)
- `Dockerfile` on arches: x86_64
  - branch [`live-engine`](https://github.com/ocurrent/ocurrent.org/tree/live-engine) built at [`ocurrent/ocurrent.org:live-engine`](https://hub.docker.com/r/ocurrent/ocurrent.org)

### [ocaml-bench/sandmark-nightly](https://github.com/ocaml-bench/sandmark-nightly)
- `Dockerfile` on arches: x86_64
  - branch [`main`](https://github.com/ocaml-bench/sandmark-nightly/tree/main) built at [`ocurrent/sandmark-nightly:live`](https://hub.docker.com/r/ocurrent/sandmark-nightly)

### [ocurrent/multicoretests-ci](https://github.com/ocurrent/multicoretests-ci)
- `Dockerfile` on arches: x86_64
  - branch [`live`](https://github.com/ocurrent/multicoretests-ci/tree/live) built at [`ocurrent/multicoretests-ci:live`](https://hub.docker.com/r/ocurrent/multicoretests-ci)

## OCaml Org services

### [ocurrent/ocurrent-deployer](https://github.com/ocurrent/ocurrent-deployer)
- `Dockerfile` on arches: x86_64
  - branch [`live-ocaml-org`](https://github.com/ocurrent/ocurrent-deployer/tree/live-ocaml-org) built at [`ocurrent/ci.ocamllabs.io-deployer:live-ocaml-org`](https://hub.docker.com/r/ocurrent/ci.ocamllabs.io-deployer)

### [ocaml/ocaml.org](https://github.com/ocaml/ocaml.org)
- `Dockerfile` on arches: x86_64
  - branch [`main`](https://github.com/ocaml/ocaml.org/tree/main) built at [`ocurrent/v3.ocaml.org-server:live`](https://hub.docker.com/r/ocurrent/v3.ocaml.org-server)
- `Dockerfile` on arches: x86_64
  - branch [`staging`](https://github.com/ocaml/ocaml.org/tree/staging) built at [`ocurrent/v3.ocaml.org-server:staging`](https://hub.docker.com/r/ocurrent/v3.ocaml.org-server)

### [ocurrent/docker-base-images](https://github.com/ocurrent/docker-base-images)
- `Dockerfile` on arches: x86_64
  - branch [`live`](https://github.com/ocurrent/docker-base-images/tree/live) built at [`ocurrent/base-images:live`](https://hub.docker.com/r/ocurrent/base-images)

### [ocurrent/ocaml-docs-ci](https://github.com/ocurrent/ocaml-docs-ci)
- `Dockerfile` on arches: x86_64
  - branch [`live`](https://github.com/ocurrent/ocaml-docs-ci/tree/live) built at [`ocurrent/docs-ci:live`](https://hub.docker.com/r/ocurrent/docs-ci)
- `docker/init/Dockerfile` on arches: x86_64
  - branch [`live`](https://github.com/ocurrent/ocaml-docs-ci/tree/live) built at [`ocurrent/docs-ci-init:live`](https://hub.docker.com/r/ocurrent/docs-ci-init)
- `docker/storage/Dockerfile` on arches: x86_64
  - branch [`live`](https://github.com/ocurrent/ocaml-docs-ci/tree/live) built at [`ocurrent/docs-ci-storage-server:live`](https://hub.docker.com/r/ocurrent/docs-ci-storage-server)
- `Dockerfile` on arches: x86_64
  - branch [`staging`](https://github.com/ocurrent/ocaml-docs-ci/tree/staging) built at [`ocurrent/docs-ci:staging`](https://hub.docker.com/r/ocurrent/docs-ci)
- `docker/init/Dockerfile` on arches: x86_64
  - branch [`staging`](https://github.com/ocurrent/ocaml-docs-ci/tree/staging) built at [`ocurrent/docs-ci-init:staging`](https://hub.docker.com/r/ocurrent/docs-ci-init)
- `docker/storage/Dockerfile` on arches: x86_64
  - branch [`staging`](https://github.com/ocurrent/ocaml-docs-ci/tree/staging) built at [`ocurrent/docs-ci-storage-server:staging`](https://hub.docker.com/r/ocurrent/docs-ci-storage-server)

### [ocurrent/opam-repo-ci](https://github.com/ocurrent/opam-repo-ci)
- `Dockerfile` on arches: x86_64, arm64
  - branch [`live`](https://github.com/ocurrent/opam-repo-ci/tree/live) built at [`ocurrent/opam-repo-ci:live`](https://hub.docker.com/r/ocurrent/opam-repo-ci)
- `Dockerfile.web` on arches: x86_64, arm64
  - branch [`live-web`](https://github.com/ocurrent/opam-repo-ci/tree/live-web) built at [`ocurrent/opam-repo-ci-web:live`](https://hub.docker.com/r/ocurrent/opam-repo-ci-web)

### [ocurrent/opam-health-check](https://github.com/ocurrent/opam-health-check)
- `Dockerfile` on arches: x86_64
  - branch [`live`](https://github.com/ocurrent/opam-health-check/tree/live) built at [`ocurrent/opam-health-check:live`](https://hub.docker.com/r/ocurrent/opam-health-check)

## Mirage Docker services

### [ocurrent/mirage-ci](https://github.com/ocurrent/mirage-ci)
- `Dockerfile` on arches: x86_64
  - branch [`live`](https://github.com/ocurrent/mirage-ci/tree/live) built at [`ocurrent/mirage-ci:live`](https://hub.docker.com/r/ocurrent/mirage-ci)

### [ocurrent/ocurrent-deployer](https://github.com/ocurrent/ocurrent-deployer)
- `Dockerfile` on arches: x86_64
  - branch [`live-mirage`](https://github.com/ocurrent/ocurrent-deployer/tree/live-mirage) built at [`ocurrent/deploy.mirage.io:live`](https://hub.docker.com/r/ocurrent/deploy.mirage.io)

### [ocurrent/caddy-rfc2136](https://github.com/ocurrent/caddy-rfc2136)
- `Dockerfile` on arches: x86_64
  - branch [`master`](https://github.com/ocurrent/caddy-rfc2136/tree/master) built at [`ocurrent/caddy-rfc2136:live`](https://hub.docker.com/r/ocurrent/caddy-rfc2136)

