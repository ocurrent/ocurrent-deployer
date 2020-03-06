# Setting up a VM host machine

The unikernels are deployed to `m1-a`, a machine provided by <https://packet.net>. To set the machine up:

1. Configure a bridge by following the instructions in
   <https://support.packet.com/kb/articles/kvm-qemu-bridging-on-a-bonded-network> (the page title is confusing;
   you want the "How to configure a bridge on a non-bonded network?" section within it). e.g.

   ```
   auto vmbr1
   iface vmbr1 inet static
       address 147.75.34.225
       netmask 255.255.255.224
       network 147.75.34.224
       broadcast 147.75.34.255
       bridge_ports none
       bridge_stp off
       bridge_fd 0
       bridge_maxwait 0
   ```

   Note that `stp` must be `off` to avoid `set forward delay failed: Numerical result out of range` error.

   You must also delete the `lo:1` configuration section, which causes Linux to think it owns all the
   elastic IPs, instead of forwarding traffic to the guests.

2. Set `net.ipv4.ip_forward=1` (also set this in `sysctl.conf`).

3. Install Docker: <https://docs.docker.com/install/linux/docker-ce/ubuntu/>.
   Note that if you start Docker before turning on IP forwarding then Docker will turn it on BUT
   it will also add an iptables rule blocking forwarded traffic from outside.

4. Add a systemd service `/etc/systemd/system/tap@.service` to manage `tap` files:

   ```
   [Service]
   Type=oneshot
   ExecStart=/sbin/ip tuntap add tap-%i mode tap
   ExecStart=/sbin/brctl addif vmbr1 tap-%i
   ExecStart=/sbin/ip link set dev tap-%i up
   RemainAfterExit=true
   ExecStop=/sbin/ip tuntap del tap-%i mode tap
   ```

5. Add a script to deploy unikernels `/usr/local/bin/deploy-mirage`:

   ```
   #!/bin/bash
   set -eu
   NAME=$1
   IMAGE=$2
   ID=$(docker container create $IMAGE)
   UNIKERNEL_PATH=/srv/unikernels/$NAME.hvt
   mkdir -p /srv/unikernels
   docker cp $ID:/unikernel.hvt $UNIKERNEL_PATH
   docker container rm $ID
   echo "Exported unikernel to $UNIKERNEL_PATH"
   echo "Restarting $NAME..."
   START=$(date +'%Y-%m-%d %H:%M:%S')
   systemctl restart $NAME
   timeout 3s journalctl --since "$START" -u $NAME.service -f || echo
   systemctl status -n 0 $NAME
   ```

6. Install the solo5 tools. I use this `Dockerfile` (adjust to match the host platform):
   ```
   FROM ocurrent/opam:ubuntu-18.04-ocaml-4.09
   RUN opam depext -i solo5-bindings-hvt
   ```
   Then build and install with:
   ```
   docker build -t solo5 .
   docker run --rm -i -w /home/opam/.opam/4.09/bin solo5 sh -c 'tar cf - solo5*' | tar xvf - -C /usr/local/bin
   ```

## Adding a unikernel guest

Create a systemd unit file for the unikernel. e.g. `/etc/systemd/system/mirage-www.service`:

```
[Unit]
Description=%N unikernel
Requires=tap@%N.service
After=tap@%N.service

[Service]
ExecStart=/usr/local/bin/solo5-hvt --mem=100 --net:service=tap-%N -- /srv/unikernels/%N.hvt \
	  --ipv4 147.75.34.226/27 --ipv4-gateway 147.75.34.225 --host 147.75.34.226

[Install]
WantedBy=multi-user.target
```

1. Change the `--ipv4` option to an unused IP address in the public address block
   (check the other unikernels to find one that is free).
2. Replace `--host` in this example with whatever options the unikernel requires.
3. Change the `--mem=` option to however much RAM the unikernel should have.

Then: `systemctl daemon-reload` and `systemctl enable mirage-www`

Finally, edit `src/pipeline.ml` so that the deployer will deploy the unikernel automatically.
