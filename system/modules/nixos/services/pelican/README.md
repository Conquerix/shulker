# Pelican

[Pelican](https://pelican.dev/) is one service family with a Panel control
plane and Wings game-server nodes. The module preserves the existing nested
`pelican.panel.*` and `pelican.wings.*` option namespaces: the Panel is an OCI
container and Wings is a native NixOS service. Panel and Wings remain separate
runtime components with distinct state, backup, and firewall boundaries.

## Deployment and options

Shulker runs both components. Its Panel uses the pinned `pelican-panel` OCI
image on loopback port 23236, and Wings uses its native service on port 23237.
Enderdragon and Warden run Wings only, each on port 23231. The generated Panel
unit is `docker-pelican-panel.service`; Wings uses the native `wings.service`
and its configuration-setup unit.

Panel options are `enable`, `impermanence`, `appUrl`, `stateDir`, and `port`.
Its default state directory is `/var/lib/pelican/panel`; the module creates
`data`, `logs`, and `plugins` with the `pelican-panel` identity. Wings options
are `enable`, `impermanence`, `openFirewall`, `stateDir`, and `port`, with
default state at `/var/lib/pelican/wings`. Wings retains its configured Docker
network at `172.55.0.0/16`; do not alter its network, node settings, image, or
component identity as part of this structural service family.

## Networking and exposure

The Panel binds only to loopback. It does not create a firewall rule, public
route, DNS record, or external account. Wings uses its configured API port and,
when `openFirewall` is enabled, opens TCP and UDP port 2022 in addition to the
upstream Wings firewall behavior. All currently enabled Wings hosts set
`openFirewall = true`. Treat any Panel proxy route and all account or node
management as live Pelican control-plane state.

## State, secrets, and backups

The Panel persists `data`, `logs`, and `plugins` when impermanence is enabled,
backs up its complete state directory with Borgmatic, and registers the
`pelican-panel-db` SQLite database. Wings persists `archives`, `backups`,
`volumes`, and `wings.db` when enabled; its Borgmatic inputs are archives and
backups, and it registers `pelican-wings-db`.

Wings uses the logical `pelicanWingsToken` secret for the `wings` and
`wings-config-setup` services. Panel secrets: none are provisioned by this
module. Never add token values, node credentials, account data, or private
identifiers to Nix, logs, commits, or documentation.

## Health, change, and recovery

After an approved deployment, verify the appropriate local component before
changing routing, clients, or nodes:

```sh
sudo systemctl status docker-pelican-panel.service wings.service --no-pager
sudo journalctl -u docker-pelican-panel.service -u wings.service --since today
```

On Shulker, also confirm the Panel loopback listener and Wings API endpoint at
their configured ports. On Wings-only hosts, verify the Wings unit, firewall
policy, Docker network, and a controlled workload lifecycle. Before changing
an image, token, port, state path, or network, validate the flake and retain a
recoverable database and state archive. Inspect restores in empty temporary
locations before replacing live data, preserve service ownership and modes,
and obtain explicit approval for destructive restoration or control-plane
credential changes.

## Related documentation

- [Services](https://github.com/Conquerix/shulker/wiki/Services)
- [Shulker host report](https://github.com/Conquerix/shulker/wiki/Host-shulker)
- [Enderdragon host report](https://github.com/Conquerix/shulker/wiki/Host-enderdragon)
- [Warden host report](https://github.com/Conquerix/shulker/wiki/Host-warden)
- [Operations](https://github.com/Conquerix/shulker/wiki/Operations)
- [Backup and restore](https://github.com/Conquerix/shulker/wiki/Operations-Backup-and-Restore)
- [Security and recovery](https://github.com/Conquerix/shulker/wiki/Operations-Security-and-Recovery)
