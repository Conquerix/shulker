# Forgejo

Shulker runs [Forgejo](https://forgejo.org/) as its native Git forge. This
module owns the NixOS Forgejo service, its declarative settings, state
persistence, dump scheduling, and secret-file references.

## Configuration and runtime

The public options are `enable`, `impermanence`, `baseUrl`, `subDomain`,
`httpPort`, `sshPort`, and `stateDir`. Defaults are disabled, `example.com`,
the `forgejo` subdomain, HTTP port 8080, SSH port 22, and
`/var/lib/forgejo`. Shulker enables impermanence and uses its configured HTTP
port. The native `forgejo` service enables LFS and scheduled dumps; its
configured dump directory is registered with Borgmatic.

The module does not create a firewall rule or reverse-proxy route. Public DNS,
TLS, proxying, and user administration are separate operational state and
must be checked live before changing them.

## State, secrets, backups, and recovery

Forgejo state lives in `stateDir` and is persisted below `/nix/persist` when
`impermanence` is enabled, preserving the evaluated Forgejo user and group.
The module uses the logical secrets `forgejoSecretKey`,
`forgejoInternalToken`, and `forgejoSMTPPassword`; never record their values.
Its backup boundary is Forgejo's evaluated dump directory, not an invented
copy of the whole state tree.

After an approved change, check `forgejo.service`, recent journal entries,
and a normal authenticated repository operation through the intended route.
Before an upgrade or restore, verify a fresh dump can be extracted into an
empty location and use a compatible Forgejo version. Restoring over live state
or changing administrator credentials requires separate approval.

## Related documentation

- [Services](https://github.com/Conquerix/shulker/wiki/Services)
- [Shulker host report](https://github.com/Conquerix/shulker/wiki/Host-shulker)
- [Backup and restore](https://github.com/Conquerix/shulker/wiki/Operations-Backup-and-Restore)
- [Security and recovery](https://github.com/Conquerix/shulker/wiki/Operations-Security-and-Recovery)
