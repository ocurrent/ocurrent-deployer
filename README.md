# Deployer

This repository contains an [OCurrent][] pipeline for deploying the
various other pipelines we use. When a new commit is pushed to the
`live` branch of a source repository, it builds a new Docker image
for the project and upgrades the service to that version.

[OCurrent]: https://github.com/ocurrent/ocurrent
