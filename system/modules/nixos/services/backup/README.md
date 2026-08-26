# Backup

This module configures Borgmatic backups for Enderdragon, Shulker, and Warden.
It owns the native Borgmatic service configuration, its retention policy, and
the source-directory integration used by other service modules.

## Configuration and runtime

The public options are `enable`, `dirs`, and `hetznerStorageBoxAccount`.
`dirs` defaults to an empty list and is sorted lexically before Borgmatic uses
it; enabled hosts set the storage-box account. The module enables the native
Borgmatic unit, keeps seven daily, four weekly, and six monthly archives, and
runs repository checks weekly and archive checks monthly. It does not run a
container or listen on a network port.

`/var/lib/borgmatic` is the unit state directory. It is persisted below
`/nix/persist` when the host enables impermanence. The logical backup-password
secret is `hetznerBorgPassword`; Borgmatic also consumes the pre-existing
`sshed25519HostKey` for its SSH transport. Secret values and storage account
identifiers must stay out of documentation and logs.

Service modules contribute their own backup paths through `backup.dirs`; do
not add a path directly without confirming ownership, retention needs, and a
restore procedure. The module preserves the existing SSH known-host entry and
the Borgmatic ZFS-device hardening contract.

## Health, changes, and recovery

After an approved deployment, inspect the unit and run the documented
Borgmatic repository check on the affected host. Inspect repository contents
before relying on a changed source list. Test restores into an empty temporary
directory; do not overwrite live service data. Changing credentials, the
repository destination, or a restore target is a separate live operation.

## Related documentation

- [Services](https://github.com/Conquerix/shulker/wiki/Services)
- [Backup and restore](https://github.com/Conquerix/shulker/wiki/Operations-Backup-and-Restore)
- [Security and recovery](https://github.com/Conquerix/shulker/wiki/Operations-Security-and-Recovery)
