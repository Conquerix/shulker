# GrapheneOS WebDAV

Warden runs [SFTPGo Community](https://github.com/drakkan/sftpgo) in portable
mode as a dedicated WebDAV target. SFTPGo was selected over a full Nextcloud
deployment because this use case needs one standards-complete WebDAV account,
not a collaboration suite. It supports WebDAV locking and password-file
authentication while portable mode avoids a mutable user database and exposed
administration interface.

The service stores phone backups under `/storage/hdd/grapheneos-backups`, and
Warden's Borgmatic job includes that directory for an off-host copy. It listens
only on `127.0.0.1:23235`; the host firewall remains closed. Pangolin should
later publish it over HTTPS and preserve the original `Host` header, which
SFTPGo requires for correct WebDAV `COPY` and `MOVE` behavior. Do not expose the
loopback HTTP listener directly because WebDAV Basic authentication requires
TLS outside the host.

Create a `GrapheneOS WebDAV` section with a `password` field in Warden's
existing item in the Shulker 1Password vault. The username is `grapheneos`;
use a strong, unique password. The checked rebuild will refuse to continue
until this field exists.

After deployment, verify the local listener and logs before adding Pangolin:

```sh
sudo systemctl status graphene-webdav
sudo journalctl -u graphene-webdav --since today
curl --fail --user grapheneos --request PROPFIND http://127.0.0.1:23235/
```

Configure GrapheneOS with the eventual HTTPS URL separately in every Android
profile that needs backups. Seedvault's WebDAV integration has had reliability
issues across server implementations, so a successful upload is not enough:
run its integrity check and perform a test restore into a disposable profile
before relying on it.

## Related documentation

- [Services](Services)
- [Warden host report](Host-warden)
- [Public services](Public-Services)
- [Operations](Operations)
- [Backup and restore](Operations-Backup-and-Restore)
- [Security and recovery](Operations-Security-and-Recovery)
