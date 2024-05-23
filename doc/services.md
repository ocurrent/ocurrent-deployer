## Deployed CI services

### ocurrent/ocurrent-deployer
- `Dockerfile` on arches: x86_64
  - branch `live-ci3` at `ocurrent/ci.ocamllabs.io-deployer:live-ci3`

### ocurrent/ocaml-ci
- `Dockerfile` on arches: x86_64, arm64
  - branch `live-engine` at `ocurrent/ocaml-ci-service:live`
- `Dockerfile.gitlab` on arches: x86_64, arm64
  - branch `live-engine` at `ocurrent/ocaml-ci-gitlab-service:live`
- `Dockerfile.web` on arches: x86_64, arm64
  - branch `live-www` at `ocurrent/ocaml-ci-web:live`
  - branch `staging-www` at `ocurrent/ocaml-ci-web:staging`

### ocurrent/opam-repo-ci
- `Dockerfile` on arches: x86_64, arm64
  - branch `live` at `ocurrent/opam-repo-ci:live`
- `Dockerfile.web` on arches: x86_64, arm64
  - branch `live-web` at `ocurrent/opam-repo-ci-web:live`

### ocurrent/opam-health-check
- `Dockerfile` on arches: x86_64
  - branch `live` at `ocurrent/opam-health-check:live`

### ocurrent/ocaml-multicore-ci
- `Dockerfile` on arches: x86_64
  - branch `live` at `ocurrent/multicore-ci:live`
- `Dockerfile.web` on arches: x86_64
  - branch `live-web` at `ocurrent/multicore-ci-web:live`

### ocurrent/ocurrent.org
- `Dockerfile` on arches: x86_64
  - branch `live-engine` at `ocurrent/ocurrent.org:live-engine`

### ocaml-bench/sandmark-nightly
- `Dockerfile` on arches: x86_64
  - branch `main` at `ocurrent/sandmark-nightly:live`

### ocurrent/multicoretests-ci
- `Dockerfile` on arches: x86_64
  - branch `live` at `ocurrent/multicoretests-ci:live`

