# WebDAV

Warden runs [SFTPGo Community](https://github.com/drakkan/sftpgo) in portable
mode as a dedicated WebDAV target. GrapheneOS devices use it for Seedvault
backups. SFTPGo is used instead of a collaboration suite because this service
needs one standards-complete WebDAV account with WebDAV locking. Portable mode
uses a password file, avoids a mutable user database, and has no exposed
administration interface.

## Declarative service boundary

`shulker.system.modules.webdav` owns the SFTPGo service, its system user and
group, and the `graphene-webdav` unit. The enabled Warden configuration sets
the data directory to `/storage/flash/grapheneos-backups`; it is created with
owner-only permissions and is included in Warden's Borgmatic sources by
default. The module's logical password secret is `grapheneWebdavPassword`.

SFTPGo listens only on `127.0.0.1:23235`; the firewall does not expose this
listener. WebDAV Basic authentication must be protected by TLS, so never
publish or use the loopback HTTP endpoint directly. A TLS-terminating reverse
proxy must preserve the original `Host` header for correct WebDAV `COPY` and
`MOVE` handling.

## Live routing and clients

The declarative service does not create a public route. Pangolin routing,
external DNS, certificates, and each Android profile's eventual HTTPS endpoint
are live operational facts: inspect and change them only through the approved
Pangolin and client procedures. When a TLS route is intentionally configured,
keep the loopback boundary, preserve `Host`, and configure it separately in
every GrapheneOS profile that needs Seedvault backups.

Seedvault's WebDAV compatibility can vary between server implementations. A
successful upload alone is insufficient: run the client integrity check and
perform a test restore into a disposable profile before relying on a backup.

## Health and maintenance

After an approved deployment, verify the local listener and service logs before
testing any reverse-proxy route:

```sh
sudo systemctl status graphene-webdav
sudo journalctl -u graphene-webdav --since today
curl --fail --user grapheneos --request PROPFIND http://127.0.0.1:23235/
```

The service requires its password-file secret and data mount before it starts.
If it does not start, inspect the unit status and journal, then confirm the
declared secret is available through the normal checked-rebuild path without
printing its value. Confirm that the data directory is mounted and writable by
the service user before changing routing or clients.

## Changes and recovery

Keep SFTPGo portable mode, its loopback listener, and the password-file
authentication boundary when changing this service. Validate configuration
changes before deployment, then verify local WebDAV behavior before making an
approved Pangolin or client change. If a change regresses backups, stop client
writes, return to a known-good system generation or configuration, and verify
the local endpoint again before restoring external access.

Borgmatic protects the backup directory off-host. Test a file restore into an
empty temporary directory before relying on recovery, and treat restoring over
existing phone backup data as a separate, deliberate operation.

## Related documentation

- [Services](https://github.com/Conquerix/shulker/wiki/Services)
- [Warden host report](https://github.com/Conquerix/shulker/wiki/Host-warden)
- [Public services](https://github.com/Conquerix/shulker/wiki/Public-Services)
- [Operations](https://github.com/Conquerix/shulker/wiki/Operations)
- [Backup and restore](https://github.com/Conquerix/shulker/wiki/Operations-Backup-and-Restore)
- [Security and recovery](https://github.com/Conquerix/shulker/wiki/Operations-Security-and-Recovery)
