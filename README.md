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

## Testing locally

To test changes to the pipeline, use:

```
dune exec -- ocurrent-deployer-local --confirm=harmless --submission-service submission.cap \
                                     --github-webhook-secret-file github-secret-file -v
                                     ocurrent/ocaml-ci
```

You will need a `submission.cap` to access an [OCluster build cluster](https://github.com/ocurrent/ocluster)
(you can run one locally fairly easily if needed), along with a `github-secret-file` containing a valid GitHub
secret for [securing webhooks](https://docs.github.com/en/developers/webhooks-and-events/webhooks/securing-your-webhooks).

Replace `ocurrent/ocaml-ci` with the GitHub repository you want to check, or omit it to check all of them.

Unlike the full pipeline, this:

- Only tries to build the deployment branches (not all PRs).
- Doesn't post the result to Slack.
- Uses anonymous access to get the branch heads.

You can supply `--github-app-id` and related options if you want to access GitHub via an app
(this gives a higher rate limit for queries, allows setting the result status and handling GitHub webhooks).

## Suggested workflows

To update a deployment that is managed by ocurrent-deployer (which could be ocurrent-deployer itself):

1. Make a PR on that project's repository targetting its master branch as usual.
2. Once it has passed CI/review, a project admin will `git push origin HEAD:live` to deploy it.
3. If it works, the PR can be merged to master.

To add new services:

1. Deploy the service(s) manually using `docker stack deploy` first.
2. Once that's working, make a PR against the ocurrent-deployer repository adding a rule to keep the services up-to-date. For the PR:
	- Drop the id\_rsa.pub key in the ~/.ssh/authorized\_keys folder on the machine where you want the deployer to deploy the container.
	- Add the machine where you want to have the deployments to the `context/meta` folder.
	- The hash for the folder inside `context/meta` is generated with `docker context create <machine_name>`.
	- Add to `known_hosts` with ssh-keyscan of the host where you are deploying the service.

[OCurrent]: https://github.com/ocurrent/ocurrent
[MirageOS]: https://mirage.io/
[Albatross]: https://github.com/hannesm/albatross
[pipeline.ml]: ./src/pipeline.ml
