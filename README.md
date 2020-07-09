# Deployer

This repository contains an [OCurrent][] pipeline for deploying the
various other pipelines we use. When a new commit is pushed to the
`live` branch of a source repository, it builds a new Docker image
for the project and upgrades the service to that version.

The main configuration is in [pipeline.ml][]. For example, one entry is:

```ocaml
ocurrent, "docker-base-images", [
  docker "Dockerfile"     ["live", "ocurrent/base-images:live", [`Toxis, "base-images_builder"]];
];
```

This says that for the <https://github.com/ocurrent/docker-base-images> repository:

- We should use Docker to build the project's `Dockerfile` (and report the status on GitHub for each branch and PR).
- For the `live` branch, we should also publish the image on Docker Hub as `ocurrent/base-images:live`
  and deploy it as the image for the `base-images_builder` Docker service on `toxis`.

The pipeline also deploys some [MirageOS][] unikernels, e.g.

```ocaml
mirage, "mirage-www", [
  unikernel "Dockerfile" ~target:"hvt" ["EXTRA_FLAGS=--tls=true"] ["master", "www"];
  unikernel "Dockerfile" ~target:"xen" ["EXTRA_FLAGS=--tls=true"] [];     (* (no deployments) *)
];
```

This builds each branch and PR of <https://github.com/mirage/mirage-www> for both `hvt` and `xen` targets.
For the `master` branch, the `hvt` unikernel is deployed as the `www` [Albatross][] service.

See [VM-host.md](./VM-host.md) for instructions about setting up a host for unikernels.

[OCurrent]: https://github.com/ocurrent/ocurrent
[MirageOS]: https://mirage.io/
[Albatross]: https://github.com/hannesm/albatross
[pipeline.ml]: ./src/pipeline.ml
