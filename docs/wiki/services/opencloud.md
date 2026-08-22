# OpenCloud family storage

Warden runs [OpenCloud](https://docs.opencloud.eu/) as the family's Dropbox-like
file-sync service. The production image is pinned by tag and digest, and its
HTTP listener is available only at `127.0.0.1:23236`. Pangolin is the sole
public entry point at `https://cloud.shulker.link`; never publish the container
port on Warden's LAN interface.

All configuration, identity metadata, and files live in the dedicated
`flash_pool/flash/storage/opencloud` dataset mounted at
`/storage/flash/opencloud`. OpenCloud uses PosixFS in non-collaborative mode:
do not edit this tree while OpenCloud is running. Metadata can live in extended
attributes or sidecar files, so copies and restores must preserve both.

Before the first deployment, create and temporarily mount the dataset:

```sh
sudo zfs create \
  -o mountpoint=legacy \
  -o quota=1.5T \
  -o compression=zstd \
  -o atime=off \
  -o acltype=posixacl \
  -o xattr=sa \
  -o dnodesize=auto \
  flash_pool/flash/storage/opencloud
sudo install -d -m 0750 /storage/flash/opencloud
sudo mount -t zfs \
  flash_pool/flash/storage/opencloud /storage/flash/opencloud
sudo chown 10001:10001 /storage/flash/opencloud
sudo chmod 0750 /storage/flash/opencloud
```

The NixOS mount unit takes over after deployment. Do not create the dataset
with a broader quota or a different mount point without updating the evaluated
host configuration and generated report too.

Create an `OpenCloud` section with an `Environment` field in Warden's existing
item in the Shulker 1Password vault. Its value is a dotenv file containing:

```dotenv
IDM_ADMIN_PASSWORD=<strong unique bootstrap password>
WEB_OIDC_CLIENT_ID=<Pocket ID web client UUID>
PROXY_OIDC_CLIENT_ID=<same Pocket ID web client UUID>
WEBFINGER_WEB_OIDC_CLIENT_ID=<same Pocket ID web client UUID>
```

The client ID is public, but keeping all first-start values in one OpNix field
allows the checked rebuild to validate the complete runtime environment. The
admin password is consumed when OpenCloud initializes IDM; later changes must
be made through OpenCloud's supported password-management flow.

In Pocket ID, create these groups and custom claims:

| Group | Claim key | Claim value |
| --- | --- | --- |
| `opencloud_admins` | `opencloud_role` | `opencloudAdmin` |
| `opencloud_spaceadmins` | `opencloud_role` | `opencloudSpaceAdmin` |
| `opencloud_users` | `opencloud_role` | `opencloudUser` |
| `opencloud_guests` | `opencloud_role` | `opencloudGuest` |

Every allowed user must belong to one of these groups. Create four public OIDC
clients with PKCE enabled:

- Web: use Pocket ID's generated UUID and callbacks
  `https://cloud.shulker.link/`,
  `https://cloud.shulker.link/oidc-callback.html`, and
  `https://cloud.shulker.link/oidc-silent-redirect.html`; set the logout callback
  to `https://cloud.shulker.link`.
- Desktop: set the client ID to `OpenCloudDesktop` and allow
  `http://127.0.0.1` plus `http://localhost` callbacks.
- Android: set the client ID to `OpenCloudAndroid` and callback to
  `oc://android.opencloud.eu`.
- iOS: set the client ID to `OpenCloudIOS` and callback to
  `oc://ios.opencloud.eu`.

Restrict each client to the OpenCloud groups. These are public PKCE clients and
must not have client secrets.

After the secret and Pocket ID objects exist, deploy with `shulker-rebuild` and
verify the loopback listener before creating a Pangolin public HTTP resource:

```sh
sudo systemctl status docker-opencloud
sudo journalctl -u docker-opencloud --since today
curl --fail --head http://127.0.0.1:23236/
```

Point `cloud.shulker.link` to `http://127.0.0.1:23236` and preserve the original
host header. Once family members have signed in, create a project space named
`Family`, add the intended members, and set its quota to 750 GiB. Newly
provisioned personal spaces receive a 200 GiB quota. Public links require a
password of at least 12 characters; set a maximum 30-day expiry when creating
each link because OpenCloud does not expose a global mandatory-expiry setting.

Warden's Borgmatic job stops OpenCloud only long enough to create the exact ZFS
snapshot `flash_pool/flash/storage/opencloud@borgmatic`, immediately restarts
the service, and backs up
`/storage/flash/opencloud/.zfs/snapshot/borgmatic`. Borg preserves ACLs and
extended attributes by default. Successful and failed jobs both remove only
that managed snapshot. Daily upload/trash cleanup requires a successful fresh
Borgmatic run first; a weekly consistency check reports PosixFS errors.

The manual snapshot path is retained in the Borg archive rather than rewritten
to the live path. For recovery, keep OpenCloud stopped, extract
`storage/flash/opencloud/.zfs/snapshot/borgmatic` into a disposable directory,
inspect it, recreate the dataset with the properties above if necessary, then
copy the snapshot contents into the empty mounted dataset with ACLs, ownership,
and xattrs preserved. Start OpenCloud only after the full tree is restored.
Validate a real browser/native-client sync and a disposable restore before
treating this service as the sole copy of family data.


## Related documentation

- [Services](https://github.com/Conquerix/shulker/wiki/Services)
- [Warden host report](https://github.com/Conquerix/shulker/wiki/Host-warden)
- [Public services](https://github.com/Conquerix/shulker/wiki/Public-Services)
- [Operations](https://github.com/Conquerix/shulker/wiki/Operations)
- [Backup and restore](https://github.com/Conquerix/shulker/wiki/Operations-Backup-and-Restore)
- [Security and recovery](https://github.com/Conquerix/shulker/wiki/Operations-Security-and-Recovery)
