# Pocket ID

Shulker runs [Pocket ID](https://pocket-id.org/) as its native identity
service. This module owns the NixOS service configuration, its local state,
SQLite registration, Borgmatic input, and secret-file references.

## Configuration and runtime

The public options are `enable`, `impermanence`, `appUrl`, `stateDir`, and
`port`. Defaults are disabled, `example.com`, `/var/lib/pocket-id`, and port
8080. Shulker enables impermanence and configures the service on its loopback
port. The native `pocket-id` unit is not a container and binds its application
listener to `127.0.0.1`; this module does not create a firewall rule or public
route.

The logical secrets are `pocketIdEncryptionKey`,
`pocketIdMaxminLicenseKey`, and `pocketIdSMTPPassword`. Their values, identity
data, and any external proxy credentials must not enter this runbook.

## State, backups, and recovery

`stateDir` is persisted below `/nix/persist` with the Pocket ID user and group
when impermanence is enabled. The module registers the Pocket ID SQLite
database as `pocket-id-db` and includes `stateDir` in Borgmatic. Database
recovery therefore requires both the service-state directory and the matching
SQLite-aware Borgmatic recovery process.

After an approved deployment, inspect `pocket-id.service`, its journal, and
the configured local listener before exercising the intended login flow.
Validate an archive by restoring into an empty location first. Do not restore
over live identity state or rotate encryption and mail secrets without a
separate approved recovery plan.

## Related documentation

- [Services](https://github.com/Conquerix/shulker/wiki/Services)
- [Shulker host report](https://github.com/Conquerix/shulker/wiki/Host-shulker)
- [Backup and restore](https://github.com/Conquerix/shulker/wiki/Operations-Backup-and-Restore)
- [Security and recovery](https://github.com/Conquerix/shulker/wiki/Operations-Security-and-Recovery)
