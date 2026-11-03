# Pangolin client

## Purpose and access

This native machine client is independent of the existing Newt site connector.
It connects Shulker to the dedicated Enderdragon private SSH resource using
Pangolin CLI 0.19.1, pinned by binary SHA-256. It does not enable a subnet
router, exit node, public listener or SSH forwarding. DNS override is disabled;
use the resource's private address rather than replacing host DNS.

Access is owned by live Pangolin policy: grant this machine only the dedicated
Overseer Enderdragon SSH resource, TCP 22, with no UDP or ICMP. Machine
administrative visibility is not a grant to every resource. Verify the effective
resource association cache after enrollment, not just the direct grant.

## Configuration and supervision

`shulker.system.modules.pangolin-client.enable` enables `pangolin-overseer.service`.
The native client runs as root with only NET_ADMIN and NET_RAW capabilities and
access to `/dev/net/tun`. It creates the `overseer-pango` interface and resource
routes. The local management API binds only to loopback port 21820. The unit
is ordered after OpNix and restarts on exit. No host firewall port is opened.

## Secrets, persistence and backups

The client ID and secret are runtime environment variables supplied by the
`overseerPangolinClientEnv` OpNix secret from Overseer's own vault item. They
never enter Nix expressions, arguments or the store. Checked rebuild validates
the exact key set before activation. Enrollment and credential rotation require
explicit authorization; never reuse Newt or another user's credentials.

Client state is root-only under `/var/lib/pangolin-overseer`, persisted below
`/nix/persist`. It has no separate Borgmatic backup: recovery uses declarative
configuration plus the credential held in 1Password; ephemeral tunnels and logs
do not need restoration. Revoke the machine in Pangolin if credentials leak.

## Validation and recovery

Before activation, run the repository's flake evaluation, build and checked
rebuild dry-activation. Inspect all restart lists, including OpNix consumers,
and stop for approval if unrelated services would be interrupted.

After activation, inspect `systemctl status pangolin-overseer`, the interface
and routes, and Pangolin's client online state and effective resource list.
Exercise private SSH using Overseer's own key and pinned Enderdragon host key.
A running process alone is not acceptance. Do not deploy a VM as part of this
client's acceptance. Disable the module and revoke its direct resource grant
for removal; do not change the existing shared SSH resource or Newt service.
