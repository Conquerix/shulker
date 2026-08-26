# Torrent

Torrent runs qBittorrent on Warden in an OCI container that includes a Proton
WireGuard tunnel and automatic Proton port forwarding. The container permits
torrent traffic only through that tunnel and has a configured in-container LAN
allowlist for the Web UI. The module also owns the shared `torrent` Unix group
used by qBittorrent and Plex's read access to completed downloads.

## Deployment and options

Warden is the only enabled host. The generated
`docker-torrent-qbittorrent.service` runs the pinned qBittorrent image, mounts
the configuration and download directories, requires the TUN device, and has
`NET_ADMIN`. The container uses its internal WireGuard configuration and
Proton port-forwarding mechanism; it is not a host WireGuard service.

The public `torrent` options are `enable`, `impermanence`, `stateDir`,
`downloadDir`, `webUiPort`, `bindAddress`, `openFirewall`, `lanNetwork`,
`portForwarding`, `puid`, `group`, `gid`, and `timeZone`. Defaults keep the Web
UI on `127.0.0.1:8080`, use the `torrent` group with GID 970, and enable
port forwarding. Warden publishes only `127.0.0.1:23232`, configures
a private LAN range as the container's VPN firewall allowlist, and stores
downloads at `/storage/hdd/torrents`.

## Networking and exposure

The published Web UI port follows `bindAddress`; Warden keeps it loopback-only
at `127.0.0.1:23232`. `openFirewall` defaults to false and Warden does not
enable it. `lanNetwork` is an allowlist inside the container's VPN firewall;
it does not publish a host LAN listener or override the loopback bind. External
torrent traffic is expected to use the WireGuard tunnel. Do not expose the Web
UI, alter the LAN CIDR, or disable the tunnel boundary without a reviewed
network change.

## State, secrets, and backups

The module creates `${stateDir}/config` with group-writable ownership and the
download directory with the setgid bit, so completed downloads retain the
shared `torrent` group. Its logical secret is `torrentWireguard`, the complete
WireGuard configuration mounted read-only as `wg0.conf`. The generated
container unit has a hard requirement on `opnix-secrets.service` and refuses to
start with an empty secret file. Secret values and VPN identifiers must never
enter Nix, logs, commits, or this runbook.

Only `${stateDir}/config` is a Borgmatic backup input. Downloads are explicitly
outside the backup boundary. Warden does not enable this module's
impermanence option, so do not infer persistent-root coverage for the state
directory from this module alone.

## Health, change, and recovery

After an approved deployment, check the container unit and its journal on
Warden:

```sh
sudo systemctl status docker-torrent-qbittorrent.service --no-pager
sudo journalctl -u docker-torrent-qbittorrent.service --since today
```

Acceptance requires confirming the loopback-only Web UI, a healthy WireGuard
tunnel, and a controlled torrent transfer with the expected port-forwarding
behavior. Do not weaken the VPN boundary merely to diagnose connectivity.
Before a container, secret, or state-path change, validate the flake and
preserve a recoverable configuration archive. Restore only the configuration
into an empty temporary location for inspection first; downloads require their
own recovery plan. Credential rotation and restoring over live state are
deliberate operations requiring explicit approval.

## Related documentation

- [Services](https://github.com/Conquerix/shulker/wiki/Services)
- [Warden host report](https://github.com/Conquerix/shulker/wiki/Host-warden)
- [Operations](https://github.com/Conquerix/shulker/wiki/Operations)
- [Backup and restore](https://github.com/Conquerix/shulker/wiki/Operations-Backup-and-Restore)
- [Security and recovery](https://github.com/Conquerix/shulker/wiki/Operations-Security-and-Recovery)
