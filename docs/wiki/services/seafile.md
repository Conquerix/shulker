# Seafile family files

Warden is configured to run [Seafile Professional Edition
13](https://manual.seafile.com/13.0/) as the family's file-sync, sharing,
search, metadata, notification, and browser Office service. Seafile is the
pilot successor to OpenCloud, but OpenCloud remains enabled as the rollback
path until the acceptance and restore gates below pass. Repository
implementation and commits do not deploy Seafile or authorize dataset,
credential, identity-provider, ingress, or other live mutations.

The seven-container matrix is pinned by tag and Linux/amd64 digest:

| Container | Image pin | Responsibility |
| --- | --- | --- |
| `seafile` | `docker.io/seafileltd/seafile-pro-mc:13.0.25@sha256:82fa05a844303912066a7ded86864dbf6fb45273f08f6448a0842863beefabb4` | Web, native-client APIs, file transfer, public links, and background work |
| `seafile-mariadb` | `docker.io/library/mariadb:10.11.18@sha256:992d5668eb9a5f153253c2f13d4e72717b7c24a27f271f47647af3b7e5a3c109` | Authoritative `ccnet_db`, `seafile_db`, and `seahub_db` state |
| `seafile-redis` | `docker.io/library/redis:7.4.10-alpine@sha256:9702d01c1f10c3ea9f48211b4362e44f154ff02d063e6f7268eba804059f53bf` | Ephemeral cache and coordination |
| `seafile-seasearch` | `docker.io/seafileltd/seasearch:1.0.4@sha256:192284f4f2fe7ca879fdfb8301dd0ebc6a5da6efaa4a99c53febfad8a75b7edc` | Derived filename, PDF, and Office-content index |
| `seafile-notification` | `docker.io/seafileltd/notification-server:13.0.21@sha256:be7b6c6887b921a86ec4990c0c8b0b57f7f5ba3046dcf0adb007bbc80abaec86` | Real-time library, lock, and permission updates over WebSocket |
| `seafile-metadata` | `docker.io/seafileltd/seafile-md-server:13.0.22@sha256:8ccee7ea9139c288a24bf1d7e29c5a1579256ee5f887eb93967e790f571eb973` | Extended properties and table, Kanban, and gallery views |
| `seafile-onlyoffice` | `docker.io/onlyoffice/documentserver:9.4.0.1@sha256:e231bc62da8c1f0c1f78188f8c7e17e67716f38955d0ad1d703cf911ad6db84b` | JWT-protected DOCX, XLSX, PPTX, and CSV browser editing |

Only three loopback listeners exist. Warden's firewall remains closed to them:

| Public service | Warden listener | Container listener |
| --- | --- | --- |
| `https://files.shulker.link` | `127.0.0.1:23239` | Seafile port 80 |
| `https://office.shulker.link` | `127.0.0.1:23240` | OnlyOffice port 80 |
| `https://files.shulker.link/notification` | `127.0.0.1:23241` | Notification port 8083 |

MariaDB, Redis, SeaSearch, and Metadata publish no host ports. Before any
deployment, inspect Warden's CPU, available memory and swap, flash-pool free
space, and Docker storage pressure. Preserve headroom for the existing Immich,
Paperless, Plex, and OpenCloud workloads; OnlyOffice alone has a 4 GiB baseline,
and two concurrent 1.5 TiB ZFS quotas do not reserve physical capacity.

## Dataset and state

With separate approval, create the empty legacy-mounted dataset exactly once:

```sh
sudo zfs create \
  -o mountpoint=legacy \
  -o quota=1.5T \
  -o compression=zstd \
  -o atime=off \
  -o acltype=posixacl \
  -o xattr=sa \
  -o dnodesize=auto \
  flash_pool/flash/storage/seafile
sudo install -d -m 0750 /storage/flash/seafile
sudo mount -t zfs \
  flash_pool/flash/storage/seafile /storage/flash/seafile
sudo zfs get -Hp -o property,value \
  quota,compression,atime,acltype,xattr,dnodesize \
  flash_pool/flash/storage/seafile
findmnt --target /storage/flash/seafile
```

The validator requires the exact numeric quota `1649267441664`, exact mount,
properties, ownership, modes, and known empty layout. It refuses an ordinary
directory, a different dataset, an unsafe or nonempty tree, or a broader quota;
it never creates the ZFS dataset. The first approved deployment runs
`seafile-validate-state --initialize` through `seafile-state.service`; subsequent
starts validate the established tree without reinitializing it. Persistent
responsibilities are:

- `shared/`: Seafile objects/configuration, Seahub data, and Metadata state;
- `database/`: MariaDB physical state;
- `search/`: rebuildable SeaSearch state;
- `onlyoffice/`: non-authoritative editor cache, generated data, and logs;
- `backups/`: writer-quiesced, validated logical SQL dump sets;
- `control/`: local acceptance and backup-ownership markers, excluded from Borg.

## 1Password and Pocket ID

In Warden's existing 1Password item, create a `Seafile` section with one
concealed `Environment` field containing exactly these twelve names and no
others:

```text
INIT_SEAFILE_MYSQL_ROOT_PASSWORD
SEAFILE_MYSQL_DB_PASSWORD
REDIS_PASSWORD
JWT_PRIVATE_KEY
SEAHUB_SECRET_KEY
INIT_SEAFILE_ADMIN_EMAIL
INIT_SEAFILE_ADMIN_PASSWORD
INIT_SS_ADMIN_USER
INIT_SS_ADMIN_PASSWORD
SEAFILE_OAUTH_CLIENT_ID
SEAFILE_OAUTH_CLIENT_SECRET
ONLYOFFICE_JWT_SECRET
```

Generate every local password, JWT key, and application secret independently;
`openssl rand -hex 32` produces a parser-safe 64-character value. Never reuse a
value, paste one into Nix, pass one on a command line, or record one in logs or
documentation. Use the intended native administrator address for its email
field, a dedicated SeaSearch administrator name, and the client ID/secret
issued by Pocket ID. The checked rebuild validates the exact key set and
reports logical names only.

With separate approval, create a confidential Pocket ID authorization-code
client named `Seafile`, restricted to a `seafile_users` group. Initial
owner-only OAuth enrollment means that `seafile_users` contains exactly the
owner and no other member. Configure this exact callback:

```text
https://files.shulker.link/oauth/callback/
```

Grant only `openid profile email`. Seafile maps immutable `sub` to the external
user identifier and uses `name` and `email` as profile attributes. Local-browser
SSO is enabled so Android, desktop sync, and SeaDrive hand authentication to
the operating-system browser. The active-account boundary is one native plus
one OAuth user initially. After a separate reviewed second-user enrollment, add
only the second approved family member to the existing `seafile_users` group;
the boundary becomes one native plus two OAuth users after second-user
enrollment. This is an exact one-to-two group-membership change with no OIDC
secret rotation or 1Password edit during second-user enrollment. Do not place
Pangolin authentication in front of the web, `/client-sso/`, OAuth callback,
API, file-transfer, static, or public link surfaces.

## Pangolin routing

Create the live routes only after all three loopback listeners pass local
health, and keep interactive Pangolin authentication disabled:

- `files.shulker.link` uses `127.0.0.1:23239` as its `/` catch-all;
- a higher-priority `/notification` target uses `127.0.0.1:23241`, strips the
  prefix so `/notification/ping` reaches `/ping`, and permits WebSocket upgrades;
- `office.shulker.link` uses the separate `127.0.0.1:23240` target.

For every target, replace client-supplied forwarding headers. Set `Host` and
`X-Forwarded-Host` to the public host, set `X-Forwarded-Proto` to `https`, and
derive `X-Forwarded-For` from the actual proxy connection. Use the deployed
Pangolin release's documented long read/connect timeout settings and unbuffered
large-transfer behavior. Nix evaluation cannot prove these live control-plane
settings: acceptance must test prefix removal, a real WebSocket upgrade,
spoofed-header rejection, a multi-gigabyte transfer, and the OnlyOffice
callback path before enabling `seafile-enable-public-health`.

## Accounts, clients, and sharing

First startup creates one native, password-capable break-glass administrator
from the protected environment. Sign in through Pocket ID as the owner, list
users, promote only that passwordless OAuth account for routine administration,
and verify the boundary:

```sh
sudo seafile-list-users
sudo seafile-promote-oauth-admin USER_ID
sudo seafile-bootstrap-status
sudo seafile-license-status
```

The initial owner OAuth account and native administrator consume two of
Seafile Pro's three named-user slots. The reviewed enrollment of the second
approved family member consumes the final slot; the mature state is exactly
one native administrator plus two passwordless OAuth users. Do not activate a
fourth user without a licensing decision. Keep the native account independent
and use this interactive, live-credential recovery only after explicit
approval and a reviewed 1Password rotation when required:

```sh
sudo seafile-reset-native-admin --restore-stored
```

Use only the official web, Android, desktop sync, and SeaDrive clients during
the pilot. Android supports manual non-media upload/download and offline
availability; automatic arbitrary-folder backup and FolderSync are not
guaranteed or approved. Disable camera upload in every mobile client—Seafile
has no documented server-side switch that enforces this preference—and use
Immich mobile backup for photos and videos.

Anonymous public download and upload links may bypass Pocket ID. Require a
strong password of at least 12 characters, use the seven-day default expiry,
and never exceed 30 days. Test signed-out use, scope, expiry, explicit
revocation, and failed reuse of a revoked link.

## Components and limitations

- SeaSearch indexes filenames plus supported PDF and Office content. Its index
  is derived and rebuilt after restore; server-encrypted libraries are not
  content-searchable.
- Notification Server uses the exact internal URL
  `http://seafile-notification:8083` and public URL
  `https://files.shulker.link/notification`. It owns no authoritative data;
  loss degrades real-time updates to polling but does not prevent stored-file
  recovery.
- Metadata Server persists its state below the shared tree, uses Redis for
  cache/events, reconciles automatically every 30 minutes, limits processing to
  100,000 files per library, and uses a 1 GiB cache. Upstream exposes no
  supported manual consistency command or dedicated health API, so checks use
  startup evidence and an end-to-end property probe. Map view stays disabled
  pending a separate Google Maps billing/security review.
- OnlyOffice edits only DOCX, XLSX, PPTX, and CSV in the approved pilot through
  `https://office.shulker.link/web-apps/apps/api/documents/api.js`. Its JWT
  authenticates editor configuration and callback traffic; Seafile still
  authorizes file download. Five-minute auto-assembly reduces the live-session
  window but does not guarantee every edit or history entry has reached a
  Seafile revision. The example application remains disabled.

## Operations, backup, and restore

Normal read-only and derived-state operations are independently invocable:

```sh
sudo systemctl status seafile-compose.service --no-pager
sudo journalctl -u seafile-compose.service --since today
sudo seafile-health-check
sudo seafile-extended-health
sudo seafile-fsck-shallow
sudo seafile-fsck-full
sudo seafile-gc-dry-run
sudo seafile-search-status
sudo seafile-search-update
sudo seafile-search-rebuild
sudo seafile-metadata-probe
sudo seafile-onlyoffice-smoke-test
sudo seafile-backup-status
```

Never automate fsck repair, non-dry-run garbage collection, credential
rotation, database restoration, or upgrade deployment. They require operator
review and a fresh successful backup.

Warden's Borgmatic hook first runs OnlyOffice's supported graceful-shutdown
preparation, stops application writers without SIGKILL, creates and validates
all three MariaDB dumps while MariaDB is still running, then stops MariaDB and
creates `flash_pool/flash/storage/seafile@borgmatic`. Production is restarted
and health-checked before the snapshot dumps are imported into an isolated
validator. Borg is armed only after that import succeeds. The exact archive
sources are:

```text
/storage/flash/seafile/.zfs/snapshot/borgmatic/shared
/storage/flash/seafile/.zfs/snapshot/borgmatic/backups
```

The search index, OnlyOffice cache/logs, physical database, control markers,
persistent application logs, and secret-bearing generated configuration are
excluded. Cleanup removes only a snapshot whose protected invocation marker,
volatile authorization, dataset, and immutable ZFS GUID all agree.

Run and inspect a fresh backup before an upgrade:

```sh
sudo borgmatic create --verbosity 1
sudo borgmatic check --force
sudo seafile-backup-status
sudo seafile-pre-upgrade-check
```

Restore rehearsals are isolated and never overwrite production. Create an empty
target on an approved filesystem, use a distinct root-only runtime directory,
and run:

```sh
sudo install -d -m 0700 /srv/seafile-restore/data
sudo seafile-restore-prepare \
  --target /srv/seafile-restore/data \
  --runtime-dir /srv/seafile-restore/runtime
# Extract one selected Borg archive into the prepared target, preserving
# numeric ownership, modes, POSIX ACLs, and extended attributes.
sudo seafile-restore-verify \
  --runtime-dir /srv/seafile-restore/runtime \
  --backup-set seafile-YYYYMMDDTHHMMSS-INVOCATION
sudo seafile-restore-teardown \
  --runtime-dir /srv/seafile-restore/runtime
```

The helpers enforce a distinct project/network/ports, generated restore-only
credentials, isolated certificates and names, capacity headroom, an exact
release matrix, checksums and imports for all three databases, read-only fsck,
Metadata configuration readability, and Seafile, Notification, and OnlyOffice
health. They do not extract archive data or automate browser login, sharing,
upload, ACL, or xattr acceptance. Perform those checks manually before relying
on the archive. Teardown removes only recorded runtime artifacts and preserves
the restored target until separately approved destruction.

For upgrades, review all seven upstream releases and migrations as one matrix,
resolve fresh Linux/amd64 digests, run `seafile-pre-upgrade-check`, update all
affected pins together, build the Warden system and contracts, deploy only with
approval, and repeat login, sync, notification, metadata, Office, search,
sharing, backup, and restore acceptance. No workflow deploys automatically.

## Media boundary, acceptance, and rollback

Immich is the sole authoritative store and user interface for photo/video
originals. Never mount, index, copy, export, or link its library through
Seafile, SeaSearch, Metadata, Seaf-FUSE, WebDAV, FolderSync, symlinks,
hardlinks, reflinks, scheduled exports, or an Immich external library. A manual
copy into a general-file library is an intentional independent Seafile object;
otherwise share the asset from Immich.

Before making Seafile authoritative during the initial owner-only stage, test
the owner OAuth account and independent native administrator; browser and
native-client SSO; Android manual operations with camera upload off; desktop
sync and SeaDrive conflicts; large and unusual-name files; permissions,
locking, versions, and audit; Notification WebSockets; Metadata views and
reconciliation; OnlyOffice editing and durable callbacks; public links;
search; restart and reboot persistence; the exact three listeners; current
health, fsck, and Borg checks; and a complete isolated restore rehearsal with
sample checksums, login, sharing, search, and a new upload.

After the second approved family member is enrolled, repeat login and client
acceptance with both OAuth users and test two-user sharing, permissions,
locking, conflict handling, Notification updates, Metadata views, and
OnlyOffice collaboration. OpenCloud retirement requires every applicable gate
for the current onboarding stage: the later two-user checks are not blockers
while `seafile_users` remains owner-only, but become mandatory as soon as the
second member is enrolled.

If acceptance fails, keep or return users to OpenCloud and leave its service,
dataset, identity objects, and secret material unchanged. Immediately before
retirement, perform a fresh live OpenCloud inventory. Retirement is allowed
only after every applicable Seafile/restore test passes and that inventory
proves either zero state or completion of a separately reviewed migration.
OpenCloud removal and dataset deletion are separate, destructive,
approval-gated work.


## Related documentation

- [Services](Services)
- [Warden host report](Host-warden)
- [Public services](Public-Services)
- [Operations](Operations)
- [Backup and restore](Operations-Backup-and-Restore)
- [Security and recovery](Operations-Security-and-Recovery)
