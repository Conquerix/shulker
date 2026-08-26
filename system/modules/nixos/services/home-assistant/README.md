# Home Assistant

[Home Assistant](https://www.home-assistant.io/) is the home-automation
service on Silverfish. This module owns its OCI container, declared state
directory, device and D-Bus access, and host firewall behavior. Integrations,
devices, automations, dashboards, and account configuration are Home Assistant
runtime state rather than declarative repository data.

## Deployment and options

Silverfish is the only enabled host. The module runs the generated
`docker-home-assistant.service` container unit from a pinned Home Assistant
image. It uses host networking and privileged mode, mounts its configuration
directory read-write, and mounts host D-Bus and `/dev` for supported local
integrations. Its declared capabilities are `NET_ADMIN` and `NET_RAW`.

The public `home-assistant` options are `enable`, `impermanence`,
`openFirewall`, `stateDir`, and `timezone`. The default state directory is
`/var/lib/home-assistant`; Silverfish enables impermanence and the firewall.
The default timezone follows the host timezone. Do not change the image,
privilege boundary, network mode, device mounts, or capabilities as part of an
ordinary service configuration edit.

## Networking and exposure

The container uses host networking. When `openFirewall` is enabled, the module
opens TCP ports 8123 and 21064; Silverfish enables that option. The module does
not declare a reverse proxy, public route, DNS record, or external account.
Treat any remote access path as live control-plane state and verify it before
changing it.

## State, secrets, and backups

The module creates `stateDir` with mode `0750` owned by `root:root` and mounts
it at `/config`. With `impermanence` enabled, it persists that directory below
`/nix/persist`. The module contributes the complete configured `stateDir` to
the shared Borgmatic input list, but Silverfish currently has the backup module
and Borgmatic disabled. That integration is therefore dormant, not evidence of
an active archive or a recoverable off-host copy.

Secrets: none are provisioned by this module. Integration tokens, device
credentials, and application account data remain Home Assistant runtime state;
never add their values to Nix, logs, commits, or this runbook.

## Health, change, and recovery

After an approved deployment, check the generated container unit and its
recent journal on Silverfish:

```sh
sudo systemctl status docker-home-assistant.service --no-pager
sudo journalctl -u docker-home-assistant.service --since today
curl --fail http://127.0.0.1:8123/
```

Confirm the intended integrations and a real automation in the Home Assistant
interface; a container start alone does not prove device access. Before an
image, state-path, or integration change, validate the flake and establish an
independently verified archive or another recovery plan. Do not assume that a
Borgmatic restore exists while the service is disabled. If an archive is later
enabled, inspect a restore in an empty temporary directory and preserve
ownership and modes before replacing live state. Do not overwrite a live
configuration or mutate device credentials without explicit approval.

## Related documentation

- [Services](https://github.com/Conquerix/shulker/wiki/Services)
- [Silverfish host report](https://github.com/Conquerix/shulker/wiki/Host-silverfish)
- [Operations](https://github.com/Conquerix/shulker/wiki/Operations)
- [Backup and restore](https://github.com/Conquerix/shulker/wiki/Operations-Backup-and-Restore)
- [Security and recovery](https://github.com/Conquerix/shulker/wiki/Operations-Security-and-Recovery)
