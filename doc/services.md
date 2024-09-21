# Deployed CI services

For a given service, the specified Dockerfile is pulled from the specified branch and built to produce an image, which is then pushed to Docker Hub with the specified tag.

## Tarides services
<https://deploy.ci.dev/>

### [ocurrent/ocurrent-deployer](https://github.com/ocurrent/ocurrent-deployer)

- `Dockerfile` on arches: x86_64
  - branch: [`live-ci3`](https://github.com/ocurrent/ocurrent-deployer/tree/live-ci3)
  - registered image: [`ocurrent/ci.ocamllabs.io-deployer:live-ci3`](https://hub.docker.com/r/ocurrent/ci.ocamllabs.io-deployer)
  - services:
    - `deployer_deployer`


### [ocurrent/ocaml-ci](https://github.com/ocurrent/ocaml-ci)

- `Dockerfile` on arches: x86_64, arm64
  - branch: [`live-engine`](https://github.com/ocurrent/ocaml-ci/tree/live-engine)
  - registered image: [`ocurrent/ocaml-ci-service:live`](https://hub.docker.com/r/ocurrent/ocaml-ci-service)
  - services:
    - `ocaml-ci_ci` @ <https://ocaml.ci.dev>

- `Dockerfile.gitlab` on arches: x86_64, arm64
  - branch: [`live-engine`](https://github.com/ocurrent/ocaml-ci/tree/live-engine)
  - registered image: [`ocurrent/ocaml-ci-gitlab-service:live`](https://hub.docker.com/r/ocurrent/ocaml-ci-gitlab-service)
  - services:
    - `ocaml-ci_gitlab` @ <https://ocaml.ci.dev>

- `Dockerfile.web` on arches: x86_64, arm64
  - branch: [`live-www`](https://github.com/ocurrent/ocaml-ci/tree/live-www)
  - registered image: [`ocurrent/ocaml-ci-web:live`](https://hub.docker.com/r/ocurrent/ocaml-ci-web)
  - services:
    - `ocaml-ci_web` @ <https://ocaml.ci.dev>

  - branch: [`staging-www`](https://github.com/ocurrent/ocaml-ci/tree/staging-www)
  - registered image: [`ocurrent/ocaml-ci-web:staging`](https://hub.docker.com/r/ocurrent/ocaml-ci-web)
  - services:
    - `test-www` @ <https://ocaml.ci.dev>


### [ocurrent/ocaml-multicore-ci](https://github.com/ocurrent/ocaml-multicore-ci)

- `Dockerfile` on arches: x86_64
  - branch: [`live`](https://github.com/ocurrent/ocaml-multicore-ci/tree/live)
  - registered image: [`ocurrent/multicore-ci:live`](https://hub.docker.com/r/ocurrent/multicore-ci)
  - services:
    - `infra_multicore-ci` @ <https://ci4.ocamllabs.io>

- `Dockerfile.web` on arches: x86_64
  - branch: [`live-web`](https://github.com/ocurrent/ocaml-multicore-ci/tree/live-web)
  - registered image: [`ocurrent/multicore-ci-web:live`](https://hub.docker.com/r/ocurrent/multicore-ci-web)
  - services:
    - `infra_multicore-ci-web` @ <https://ci4.ocamllabs.io>


### [ocurrent/ocurrent.org](https://github.com/ocurrent/ocurrent.org)

- `Dockerfile` on arches: x86_64
  - branch: [`live-engine`](https://github.com/ocurrent/ocurrent.org/tree/live-engine)
  - registered image: [`ocurrent/ocurrent.org:live-engine`](https://hub.docker.com/r/ocurrent/ocurrent.org)
  - services:
    - `ocurrent_org_watcher` @ <https://ci3.ocamllabs.io>


### [ocaml-bench/sandmark-nightly](https://github.com/ocaml-bench/sandmark-nightly)

- `Dockerfile` on arches: x86_64
  - branch: [`main`](https://github.com/ocaml-bench/sandmark-nightly/tree/main)
  - registered image: [`ocurrent/sandmark-nightly:live`](https://hub.docker.com/r/ocurrent/sandmark-nightly)
  - services:
    - `sandmark_sandmark` @ <https://ci3.ocamllabs.io>


### [ocurrent/multicoretests-ci](https://github.com/ocurrent/multicoretests-ci)

- `Dockerfile` on arches: x86_64
  - branch: [`live`](https://github.com/ocurrent/multicoretests-ci/tree/live)
  - registered image: [`ocurrent/multicoretests-ci:live`](https://hub.docker.com/r/ocurrent/multicoretests-ci)
  - services:
    - `infra_multicoretests-ci` @ <https://ci4.ocamllabs.io>


## OCaml Org services
<https://deploy.ci.ocaml.org>

### [ocurrent/ocurrent-deployer](https://github.com/ocurrent/ocurrent-deployer)

- `Dockerfile` on arches: x86_64
  - branch: [`live-ocaml-org`](https://github.com/ocurrent/ocurrent-deployer/tree/live-ocaml-org)
  - registered image: [`ocurrent/ci.ocamllabs.io-deployer:live-ocaml-org`](https://hub.docker.com/r/ocurrent/ci.ocamllabs.io-deployer)
  - services:
    - `infra_deployer`


### [ocaml/ocaml.org](https://github.com/ocaml/ocaml.org)

- `Dockerfile` on arches: x86_64
  - branch: [`main`](https://github.com/ocaml/ocaml.org/tree/main)
  - registered image: [`ocurrent/v3.ocaml.org-server:live`](https://hub.docker.com/r/ocurrent/v3.ocaml.org-server)
  - services:
    - `infra_www` @ <https://v3b.ocaml.org>

- `Dockerfile` on arches: x86_64
  - branch: [`staging`](https://github.com/ocaml/ocaml.org/tree/staging)
  - registered image: [`ocurrent/v3.ocaml.org-server:staging`](https://hub.docker.com/r/ocurrent/v3.ocaml.org-server)
  - services:
    - `infra_www` @ <https://v3c.ocaml.org>


### [ocurrent/docker-base-images](https://github.com/ocurrent/docker-base-images)

- `Dockerfile` on arches: x86_64
  - branch: [`live`](https://github.com/ocurrent/docker-base-images/tree/live)
  - registered image: [`ocurrent/base-images:live`](https://hub.docker.com/r/ocurrent/base-images)
  - services:
    - `base-images_builder` @ <https://images.ci.ocaml.org>


### [ocurrent/ocaml-docs-ci](https://github.com/ocurrent/ocaml-docs-ci)

- `Dockerfile` on arches: x86_64
  - branch: [`live`](https://github.com/ocurrent/ocaml-docs-ci/tree/live)
  - registered image: [`ocurrent/docs-ci:live`](https://hub.docker.com/r/ocurrent/docs-ci)
  - services:
    - `infra_docs-ci` @ <https://docs.ci.ocaml.org>

- `docker/init/Dockerfile` on arches: x86_64
  - branch: [`live`](https://github.com/ocurrent/ocaml-docs-ci/tree/live)
  - registered image: [`ocurrent/docs-ci-init:live`](https://hub.docker.com/r/ocurrent/docs-ci-init)
  - services:
    - `infra_init` @ <https://docs.ci.ocaml.org>

- `docker/storage/Dockerfile` on arches: x86_64
  - branch: [`live`](https://github.com/ocurrent/ocaml-docs-ci/tree/live)
  - registered image: [`ocurrent/docs-ci-storage-server:live`](https://hub.docker.com/r/ocurrent/docs-ci-storage-server)
  - services:
    - `infra_storage-server` @ <https://docs.ci.ocaml.org>

- `Dockerfile` on arches: x86_64
  - branch: [`staging`](https://github.com/ocurrent/ocaml-docs-ci/tree/staging)
  - registered image: [`ocurrent/docs-ci:staging`](https://hub.docker.com/r/ocurrent/docs-ci)
  - services:
    - `infra_docs-ci` @ <https://staging.docs.ci.ocaml.org>

- `docker/init/Dockerfile` on arches: x86_64
  - branch: [`staging`](https://github.com/ocurrent/ocaml-docs-ci/tree/staging)
  - registered image: [`ocurrent/docs-ci-init:staging`](https://hub.docker.com/r/ocurrent/docs-ci-init)
  - services:
    - `infra_init` @ <https://staging.docs.ci.ocaml.org>

- `docker/storage/Dockerfile` on arches: x86_64
  - branch: [`staging`](https://github.com/ocurrent/ocaml-docs-ci/tree/staging)
  - registered image: [`ocurrent/docs-ci-storage-server:staging`](https://hub.docker.com/r/ocurrent/docs-ci-storage-server)
  - services:
    - `infra_storage-server` @ <https://staging.docs.ci.ocaml.org>


### [ocurrent/opam-repo-ci](https://github.com/ocurrent/opam-repo-ci)

- `Dockerfile` on arches: x86_64, arm64
  - branch: [`live`](https://github.com/ocurrent/opam-repo-ci/tree/live)
  - registered image: [`ocurrent/opam-repo-ci:live`](https://hub.docker.com/r/ocurrent/opam-repo-ci)
  - services:
    - `opam-repo-ci_opam-repo-ci` @ <https://opam.ci.ocaml.org>

- `Dockerfile.web` on arches: x86_64, arm64
  - branch: [`live-web`](https://github.com/ocurrent/opam-repo-ci/tree/live-web)
  - registered image: [`ocurrent/opam-repo-ci-web:live`](https://hub.docker.com/r/ocurrent/opam-repo-ci-web)
  - services:
    - `opam-repo-ci_opam-repo-ci-web` @ <https://opam.ci.ocaml.org>


### [ocurrent/opam-health-check](https://github.com/ocurrent/opam-health-check)

- `Dockerfile` on arches: x86_64
  - branch: [`live`](https://github.com/ocurrent/opam-health-check/tree/live)
  - registered image: [`ocurrent/opam-health-check:live`](https://hub.docker.com/r/ocurrent/opam-health-check)
  - services:
    - `infra_opam-health-check` @ <https://check.ci.ocaml.org>
    - `infra_opam-health-check-freebsd` @ <https://check.ci.ocaml.org>


## Mirage Docker services
<https://deploy.mirage.io/>

### [ocurrent/mirage-ci](https://github.com/ocurrent/mirage-ci)

- `Dockerfile` on arches: x86_64
  - branch: [`live`](https://github.com/ocurrent/mirage-ci/tree/live)
  - registered image: [`ocurrent/mirage-ci:live`](https://hub.docker.com/r/ocurrent/mirage-ci)
  - services:
    - `infra_mirage-ci` @ <https://ci.mirage.io>


### [ocurrent/ocurrent-deployer](https://github.com/ocurrent/ocurrent-deployer)

- `Dockerfile` on arches: x86_64
  - branch: [`live-mirage`](https://github.com/ocurrent/ocurrent-deployer/tree/live-mirage)
  - registered image: [`ocurrent/deploy.mirage.io:live`](https://hub.docker.com/r/ocurrent/deploy.mirage.io)
  - services:
    - `infra_deployer` @ <https://ci.mirage.io>


### [ocurrent/caddy-rfc2136](https://github.com/ocurrent/caddy-rfc2136)

- `Dockerfile` on arches: x86_64
  - branch: [`master`](https://github.com/ocurrent/caddy-rfc2136/tree/master)
  - registered image: [`ocurrent/caddy-rfc2136:live`](https://hub.docker.com/r/ocurrent/caddy-rfc2136)
  - services:
    - `infra_caddy` @ <https://ci.mirage.io>


