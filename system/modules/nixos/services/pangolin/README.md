# Pangolin

Pangolin is Shulker's edge control plane. The module runs the Gerbil, Pangolin,
and Traefik OCI containers on the dedicated `pangolin` bridge. Gerbil and
Pangolin use that bridge; Traefik shares Gerbil's network namespace. These
runtime names, images, mounts, and dependency relationships are part of the
existing control plane and must remain intact during structural changes.

## Networking and runtime

Gerbil publishes UDP ports 51820 and 21820 plus TCP ports 443 and 80 through
Docker. These edge publications are not NixOS firewall rules and must not be
converted to loopback bindings or otherwise changed here. The generated units
are `docker-gerbil.service`, `docker-pangolin.service`,
`docker-traefik.service`, `docker-network-pangolin.service`, and
`docker-compose-pangolin-root.target`. The network unit's existing stop action
removes the Docker bridge; do not execute or alter it without an approved
operational change.

## State, backup, and recovery

The public options are `enable`, `impermanence`, and `stateDir`; the default
state directory is `/var/lib/pangolin`. When persistence is enabled, the module
persists that directory below `/nix/persist`, contributes it to Borgmatic, and
registers the Pangolin SQLite database for backup. The control-plane
configuration includes runtime-generated material. Preserve the state and its
ownership during recovery; never copy generated configuration, credentials, or
private identifiers into source or documentation.

Before an approved image, port, state, route, or control-plane change, validate
the flake and establish a recovery plan with an inspected archive. Do not
replace live state or mutate credentials during a structural change.

## Topology publication boundary

The separate Wiki Integration-API pipeline publishes only the sanitized
`topology/public.json` view. Its publication credentials and helpers are
external to this service module and must remain separate from generated
Pangolin state. Operators should follow the automation runbook, including its
helper restart and rollback warning, rather than duplicate a live procedure
here: [Automation](https://github.com/Conquerix/shulker/wiki/Automation).

## Related documentation

- [Services](https://github.com/Conquerix/shulker/wiki/Services)
- [Shulker host report](https://github.com/Conquerix/shulker/wiki/Host-shulker)
- [Backup and restore](https://github.com/Conquerix/shulker/wiki/Operations-Backup-and-Restore)
- [Security and recovery](https://github.com/Conquerix/shulker/wiki/Operations-Security-and-Recovery)
