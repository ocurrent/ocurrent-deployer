#!/bin/sh

# Create Docker Context
docker context create "ci3.ocamllabs.io" --description "Ci3 - Tarides" --docker "host=ssh://root@ci3.ocamllabs.io"
docker context create "ci4.ocamllabs.io" --description "Ci4 - Tarides" --docker "host=ssh://root@ci4.ocamllabs.io"
docker context create "ci.mirage.io" --description "Ci - Mirage" --docker "host=ssh://root@ci.mirage.io"
docker context create "ci.ocamllabs.io" --description "Toxis - Tarides" --docker "host=ssh://root@ci.ocamllabs.io"
docker context create "deploy.ci.ocaml.org" --description "OCaml - deploy.ci.ocaml.org" --docker "host=ssh://root@deploy.ci.ocaml.org"
docker context create "dev1.ocamllabs.io" --description "OCaml - opam-repo-ci" --docker "host=ssh://root@dev1.ocamllabs.io"
docker context create "docs.ci.ocaml.org" --description "OCaml - docs.ci.ocaml.org" --docker "host=ssh://root@docs.ci.ocaml.org"
docker context create "docs-staging.sw.ocaml.org" --description "Staging for docs.ci.ocaml.org" --docker "host=ssh://root@docs-staging.sw.ocaml.org"
docker context create "opam-3.ocaml.org" --description "OPAM - opam-3.ocaml.org" --docker "host=ssh://root@opam-3.ocaml.org"
docker context create "opam-4.ocaml.org" --description "OPAM - opam-4.ocaml.org" --docker "host=ssh://root@opam-4.ocaml.org"
docker context create "opam-5.ocaml.org" --description "OPAM - opam-5.ocaml.org" --docker "host=ssh://root@opam-5.ocaml.org"
docker context create "v2.ocaml.org" --description "OCaml - v2.ocaml.org" --docker "host=ssh://root@v2.ocaml.org"
docker context create "v3b.ocaml.org" --description "OCaml - www.ocaml.org" --docker "host=ssh://root@v3b.ocaml.org"
docker context create "v3c.ocaml.org" --description "OCaml - staging.ocaml.org" --docker "host=ssh://root@v3c.ocaml.org"
docker context create "watch.ocaml.org" --description "OCaml - watch.ocaml.org" --docker "host=ssh://root@watch.ocaml.org"
docker context create "staging.tarides.com" --description "Tarides - staging.tarides.com" --docker "host=ssh://root@staging.tarides.com"

# Create AWS context
mkdir ~/.aws
echo "[profile default]" > ~/.aws/config
echo "region = us-east-1" >> ~/.aws/config
docker context create ecs --profile default awsecs

# Generate known_hosts file
mkdir ~/.ssh
for host in \
  ci3.ocamllabs.io \
  ci4.ocamllabs.io \
  ci.mirage.io \
  ci.ocamllabs.io \
  deploy.ci.ocaml.org \
  dev1.ocamllabs.io \
  docs.ci.ocaml.org \
  docs-staging.sw.ocaml.org \
  opam-3.ocaml.org \
  opam-4.ocaml.org \
  opam-5.ocaml.org \
  v2.ocaml.org \
  v3b.ocaml.org \
  v3c.ocaml.org \
  watch.ocaml.org \
  staging.tarides.com \
  147.75.84.37 ; do
  ssh-keyscan -H -t ecdsa-sha2-nistp256 $host >> ~/.ssh/known_hosts
done
chmod 700 ~/.ssh
chmod 600 ~/.ssh/known_hosts

# Add the deployer key
echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDAyRYpH3cy4s0t/yXM27c5quXwTC4+vaqGl43jaA9EMxnHLlQLP69aixi9/6Y0jN3RgNsL8CdOHKXNdKet2o/uqK7p8YQnrXKgoYooCNS+vg0NAL0QqE/UMryBv0nFa6PIKeWmjId4qoKd/tlkkvBdtuhBk4cg7K8wQYzqC4eJC8Iby4ZswadZl2GW2LiGuj3CAS6XuAD9dhVpZJrOcl+5RyHMnxT8J4iM8JCI2hlmp1+D1UGmaDjuPc7IChxx9+zx0XsYHqAkNoxFGYoI6IejcTIF9VGKdHtUOFcRIi3F50zRTKqLLyE7Wx9XiID13NVIyJOsLQB/MPGbcOCPWmsp user@dev" > ~/.ssh/id_rsa.pub
ln -s /run/secrets/deployer-ssh-key ~/.ssh/id_rsa
