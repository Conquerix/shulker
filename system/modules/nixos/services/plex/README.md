# Plex

Warden runs [Plex Media Server](https://www.plex.tv/) as the fleet's media
catalog and playback service. This module owns the native NixOS service, its
local state location, host access, and hardware-transcoding permissions. Media
library definitions, Plex account state, and any remote-access configuration
are managed by Plex itself rather than declared in this repository.

## Deployment and architecture

Plex runs directly as `plex.service` under the `plex` user and group; it is not
a container. Warden is the only enabled host. The evaluated configuration uses
`/var/lib/plex`, enables hardware-transcoding access, keeps the host firewall
closed, and adds the `plex` user to the shared `torrent` group so it can read
finished downloads.

The public module options are:

| Option | Default | Responsibility |
| --- | --- | --- |
| `enable` | `false` | Run Plex Media Server. |
| `dataDir` | `/var/lib/plex` | Store Plex's database, metadata, and cache. |
| `openFirewall` | `false` | Open Plex's standard LAN and discovery ports. |
| `hardwareTranscoding` | `true` | Add `plex` to the `render` and `video` groups. |
| `extraGroups` | `[]` | Grant access to separately owned media directories. |
| `impermanence` | `false` | Persist `dataDir` below `/nix/persist`. |

Hardware group membership only makes render devices available. Actual
accelerated playback still depends on compatible hardware and drivers, Plex
settings, the media format, and an eligible Plex subscription.

## Networking and exposure

Warden keeps `openFirewall = false`. The module therefore does not open Plex's
TCP or UDP ports to the LAN, although Plex still owns its normal local
listeners, including TCP port 32400. The repository declares no public Plex
URL or Pangolin resource. Any remote-access or proxy path is external runtime
state and must be verified live before it is changed.

Do not enable the broad Plex firewall preset merely to solve a proxy problem.
Identify the intended clients and exposure model first, then open only the
access that model requires.

## State, secrets, and backups

`/var/lib/plex` contains the Plex database, metadata, preferences, and cache.
Warden enables `impermanence`, so that directory persists across ephemeral-root
reboots with `plex:plex` ownership. Library media lives outside the Plex data
directory; the current module only grants read access through the `torrent`
group and does not declare the library paths.

Secrets: none are provisioned by this module or by 1Password. Plex account
credentials, claim tokens, and server tokens are runtime-managed values and
must never be added to Nix or documentation.

Backups: none are registered by this module. Warden's Borgmatic source list
does not include `/var/lib/plex`, so persistence is not an off-host recovery
copy. Loss of this directory can mean rebuilding the server, rescanning media,
and losing metadata, preferences, and watch state even when the media files
survive.

## Health, change, and recovery

Check the service, recent logs, and local identity endpoint on Warden:

```sh
sudo systemctl status plex.service --no-pager
sudo journalctl -u plex.service --since today
curl --fail http://127.0.0.1:32400/identity
```

Acceptance also requires direct playback, a library scan, and one real
hardware transcode while observing the selected render device. A successful
HTTP response alone does not validate media access or acceleration.

Plex packages follow the repository's pinned Nixpkgs revision. Before an
upgrade or `dataDir` change, review upstream release notes and establish a
recoverable metadata backup; copying the live database is not a safe backup
procedure. A restore must be performed with Plex stopped, preserve ownership
and modes, and use a compatible server version. Destructive restore work and
Plex-account mutations require explicit approval. If no metadata backup
exists, recover by redeploying Plex, reclaiming the server through the approved
account flow, re-adding the library roots, and rescanning the surviving media.

## Related documentation

- [Services](https://github.com/Conquerix/shulker/wiki/Services)
- [Warden host report](https://github.com/Conquerix/shulker/wiki/Host-warden)
- [Operations](https://github.com/Conquerix/shulker/wiki/Operations)
- [Backup and restore](https://github.com/Conquerix/shulker/wiki/Operations-Backup-and-Restore)
- [Security and recovery](https://github.com/Conquerix/shulker/wiki/Operations-Security-and-Recovery)
