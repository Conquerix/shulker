# Nextcloud

Nextcloud runs on Shulker through Nextcloud All-in-One (AIO). This module owns
only the AIO master container, its named master-configuration volume, and the
`nextcloud-aio` Docker network. AIO itself creates and owns the child
containers and Docker-managed volumes at runtime.

## Deployment and networking

The public options are `enable`, `mainPort`, and `aioPort`. The configured
Apache application listener and AIO master admin listener are distinct: the
module passes `mainPort` to AIO for Apache and publishes the master admin
listener on loopback at `aioPort`. Shulker uses loopback ports for both. The
module creates no firewall rule, public route, state directory, or
impermanence setting.

The Nix-owned runtime consists of
`docker-nextcloud-aio-mastercontainer.service`,
`docker-network-nextcloud-aio.service`,
`docker-volume-nextcloud_aio_mastercontainer.service`, and
`docker-compose-nextcloud-aio-root.target`. The network and volume are runtime
resources for the master; do not treat their existence as ownership of AIO's
child services or application data.

## Backup, secrets, and recovery boundary

This module has no module-owned secret, Borgmatic source entry, SQLite
registration, or direct backup coverage. AIO child containers and its
Docker-managed volumes are externally owned runtime state and are not directly
covered by Borgmatic. Their backup and recovery posture must be established
through AIO and the live service before a change; this runbook makes no
recovery guarantee for them.

Before an approved deployment or AIO change, validate the flake and confirm a
safe recovery plan for the external AIO-owned data. Afterwards, inspect the
master unit and verify the intended loopback endpoint. Do not mutate AIO
configuration, child containers, Docker volumes, accounts, credentials, or
public routing during a structural module change.

## Related documentation

- [Services](https://github.com/Conquerix/shulker/wiki/Services)
- [Shulker host report](https://github.com/Conquerix/shulker/wiki/Host-shulker)
- [Backup and restore](https://github.com/Conquerix/shulker/wiki/Operations-Backup-and-Restore)
- [Security and recovery](https://github.com/Conquerix/shulker/wiki/Operations-Security-and-Recovery)
