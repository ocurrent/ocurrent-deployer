# Deployer

This repository contains an [OCurrent][] pipeline for deploying the
various other pipelines we use. When a new commit is pushed to the
`live` branch of a source repository, it builds a new Docker image
for the project and upgrades the service to that version.

This pipeline also deploys some [MirageOS][] unikernels.
See [VM-host.md](./VM-host.md) for instructions about that.

[OCurrent]: https://github.com/ocurrent/ocurrent
[MirageOS]: https://mirage.io/
