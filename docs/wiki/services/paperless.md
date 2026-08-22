# Paperless family documents

Warden runs [Paperless-ngx](https://docs.paperless-ngx.com/) as the family's
authoritative searchable document archive. It is deliberately separate from
OpenCloud: OpenCloud remains general file sync and collaboration, while
Paperless owns document originals, PDF/A renditions, thumbnails, OCR text,
metadata, permissions, search indexes, and ingestion history. Do not add any
Paperless-managed directory to OpenCloud or edit it while Paperless is running.

The generated Compose stack contains Paperless-ngx `3.0.5`, PostgreSQL 18,
Valkey 9, Gotenberg 8.34, and Apache Tika 3.2.3.0. All five Linux/amd64 images
are pinned by release tag and immutable digest. Paperless listens only on
`127.0.0.1:23238`; PostgreSQL, Valkey, Gotenberg, and Tika publish no host
ports. Pangolin is the sole public path at
`https://documents.shulker.link`.

## Storage and secrets

All persistent state uses the dedicated legacy-mounted dataset
`flash_pool/flash/storage/paperless` at `/storage/flash/paperless`. Its 500 GiB
quota is an upper bound, not preallocated space. Before the first deployment,
create and temporarily mount it:

```sh
sudo zfs create \
  -o mountpoint=legacy \
  -o quota=500G \
  -o compression=zstd \
  -o atime=off \
  -o acltype=posixacl \
  -o xattr=sa \
  -o dnodesize=auto \
  flash_pool/flash/storage/paperless
sudo install -d -m 0750 /storage/flash/paperless
sudo mount -t zfs \
  flash_pool/flash/storage/paperless /storage/flash/paperless
sudo zfs get -Hp -o property,value \
  quota,compression,atime,acltype,xattr,dnodesize \
  flash_pool/flash/storage/paperless
```

The quota must evaluate to `536870912000` bytes. `paperless-state.service`
refuses to start the stack if the mounted dataset, quota, or any required ZFS
property differs. It owns application paths as UID/GID 10002 and the database
and broker paths as UID/GID 999.

Create a `Paperless` section with an `Environment` field in Warden's existing
Shulker 1Password item. Store a systemd-compatible environment document with
exactly these keys and their real values:

- `PAPERLESS_SECRET_KEY`: a stable value generated with a cryptographically
  secure random generator;
- `PAPERLESS_DB_PASSWORD`: a unique PostgreSQL password;
- `PAPERLESS_OIDC_CLIENT_ID`: the Pocket ID client identifier;
- `PAPERLESS_OIDC_CLIENT_SECRET`: the confidential Pocket ID client secret;
- `PAPERLESS_FASTMAIL_USERNAME`: the dedicated Fastmail service account;
- `PAPERLESS_FASTMAIL_APP_PASSWORD`: an app password limited to mail access.

The evaluated secret is named `paperlessEnv`. The checked rebuild validates
its 1Password reference before deployment. Compose receives values only in its
process environment; generated Nix store files, reports, and Wiki pages contain
placeholders and logical field names only.

The native break-glass administrator password is application-managed and is
not a seventh `paperlessEnv` key. Store it as a separate concealed field in
1Password. Use a strong, unique value because this credential remains valid
for the Django administrator and can obtain a local API token from
`/api/token/` even though the regular Paperless frontend login is disabled.

## Pocket ID login and break-glass administration

Create these groups in Pocket ID and identically named groups in Paperless:

| Group | Purpose |
| --- | --- |
| `paperless_users` | Normal document users and owners |
| `paperless_family` | Object-level view/change access to family documents |
| `paperless_admins` | Privileged configuration and recovery |

All family members belong to `paperless_users` and `paperless_family`.
Designated administrators additionally belong to `paperless_admins`. Create one
confidential authorization-code Pocket ID client restricted to the approved
groups. Its callback is:

```text
https://documents.shulker.link/accounts/oidc/pocket-id/login/callback/
```

Paperless automatically provisions allowed OIDC users, synchronizes the
`groups` claim on login, disables regular frontend login, and redirects to
Pocket ID. Normal users and additional OIDC administrators remain passwordless.
The policy permits exactly one password-capable native break-glass
administrator. Link that account to Pocket ID for normal use, and do not assign
a native password to any other Paperless account.

OIDC needs the production callback during initial provisioning. Create the
Pangolin resource before the first login, but initially protect the entire
resource with Pangolin authentication and grant access only to the owner. On a
new or restored instance:

```sh
sudo paperless-bootstrap-groups
# Create the first native administrator through Paperless's private first-run flow.
# Link that same account to Pocket ID from My Profile, then verify a fresh OIDC login.
sudo paperless-list-users
# Promote only additional passwordless OIDC administrators when needed.
sudo paperless-promote-oidc-admin USERNAME
sudo paperless-list-users
```

The break-glass account must report `usable_password=True`, staff and
superuser authority, and a linked Pocket ID login. Verify recovery at
`https://documents.shulker.link/admin/login/?next=/`, then return to normal use
through Pocket ID. Pass the exact OIDC username reported by
`paperless-list-users` when promoting an additional administrator; promotion
intentionally refuses any account with a usable password. Configure permissions
and ingestion privately before replacing the temporary whole-resource gate
with the final policy.

The final policy keeps a Pangolin-authenticated /admin recovery surface while
allowing native clients, OIDC, and administrator-created shares to reach
Paperless directly. Pangolin matches path patterns segment by segment, so add
each of these as a separate **Pass to Auth** rule above every bypass rule:

```text
/admin
/admin/*
/admin/*/*
/admin/*/*/*
/admin/*/*/*/*
/admin/*/*/*/*/*
```

The first four wildcard depths cover the current Paperless 3.0.5 Django
administrator routes, including `/admin/auth/user/<id>/change/`; the fifth is an
explicit safety margin. A deeper route would fall through, so inspect the
administrator URLs on every upgrade and add another Pass to Auth depth before
deployment if needed. In a signed-out session, probe the exact path and every
configured descendant depth and require the Pangolin challenge before any
Paperless response.

Next add **Bypass Auth** rules for `/share` and `/share/*`, then a final general
Bypass Auth rule forwarding every other path to `http://127.0.0.1:23238`.
Paperless 3.0.5 share URLs contain one slug segment; recheck this route shape on
upgrade. Paperless remains the authentication layer for web, API, media,
static, and OIDC callback traffic; only `/admin` receives the additional
Pangolin gate.

This leaves an administrator-only public /share bearer-link surface. Ordinary
groups retain no share-link permissions. Give each link the shortest practical
expiry, share it as a secret, and revoke it when no longer needed. Anyone
holding a live URL can access its document without Pocket ID or Pangolin
authentication.

The following removal procedure is for an additional passwordless OIDC
administrator. Never run it against the sole native break-glass administrator.
To replace that recovery account, first create, link, and successfully test a
new native break-glass administrator from outside the current session. Then
revoke active Paperless authority and disable the old account so OIDC group
synchronization cannot restore its administrator group during the external
identity change:

```sh
sudo paperless-revoke-admin --disable-user USERNAME
# Remove paperless_admins membership or Paperless client eligibility in Pocket ID.
# Re-enable the existing non-admin account only when continued access is intended.
sudo paperless-enable-user USERNAME
```

The command terminates that user's sessions, revokes API tokens, removes the
administrator group, clears staff/superuser flags, and disables the account.
`paperless-enable-user` refuses password-capable users and any account that
still has local administrator authority. Run it only after the Pocket ID change
has completed; omit it when all Paperless access should remain revoked. A
disabled password-capable recovery account is deliberately not re-enabled by
this helper.

## Permissions and intake

Normal users receive only the global permissions required to upload and use
shared metadata. Ownership and object-level permissions protect documents:

- web/API uploads are owned by the authenticated uploader and private by
  default;
- a private mail or future scanner route assigns its named OIDC user and grants
  no family access;
- the family route assigns the designated administrator and a privileged
  workflow grants `paperless_family` view/change access;
- owners may explicitly grant `paperless_family` access later;
- administrators retain recovery access.

Only administrators may manage workflows or mail accounts. Configure one
family-intake workflow that matches the managed `Shulker route - family` mail
rule, assigns the designated administrator, and grants the family group view
and change permissions. Private managed rules must not invoke this workflow.
Test the resulting object permissions with two ordinary OIDC users; an
administrator test does not prove isolation.

The dedicated Fastmail account uses `imap.fastmail.com:993` over SSL. Each
enabled person signs in to Paperless once before receiving a private route so
their internal OIDC user exists. Create the `Paperless/Processed` IMAP folder,
then prepare a root-owned mode-0600 JSON file outside Git. It is an array whose
objects contain exactly:

| Field | Value |
| --- | --- |
| `name` | Unique lowercase route identifier using letters, digits, and hyphens; the family route must be exactly `family` |
| `address` | Exact Fastmail alias or plus-addressed recipient |
| `owner` | Exact username reported by `paperless-list-users` |
| `scope` | `private` or `family`; exactly one route is `family`, and only the route named `family` may use it |

Apply the routes without exposing credentials:

```sh
sudo paperless-bootstrap-fastmail \
  --admin-username USERNAME \
  --routes-json /run/paperless-fastmail-routes.json
sudo rm -f /run/paperless-fastmail-routes.json
```

Use an additional passwordless OIDC administrator for `--admin-username`, not
the native break-glass account; the helper intentionally refuses any
password-capable administrator or route owner. The idempotent command upserts
only `Fastmail Paperless` and rules prefixed `Shulker route - `. It accepts
attachments, applies the global `Source: Fastmail` tag, assigns the route
owner, moves successfully processed mail to `Paperless/Processed`, and removes
only obsolete rules carrying its own prefix. Failed processing remains visible
in Paperless task history and the source mailbox.

The consume tree reserves `family` and `private` routes for a future scanner
adapter, but no SMB, SFTP, FTP, WebDAV, or scanner listener is enabled. Once a
scanner is selected, its adapter must write atomically or use a stability delay
and must map each private drop to an existing OIDC user.

Paperless OCR uses `fra+eng+deu`, with French full-text stemming and French,
English, and German date parsing. Automatic archive generation retains the
unaltered original and produces PDF/A when appropriate. Tika and Gotenberg add
DOCX, XLSX, PPTX, ODT, and related Office formats. Duplicate content is retained
and flagged for review, the audit log is enabled, and deleted documents remain
recoverable in trash for 90 days.

## Health and acceptance

Image pulling is serialized in a separate unit with a bounded two-hour window;
the webserver health check has a 30-minute startup grace period and Compose
waits at most 35 minutes. Verify the local stack before changing Pangolin:

```sh
sudo systemctl status \
  paperless-state.service \
  paperless-image-pull.service \
  paperless-compose.service --no-pager
sudo systemctl start paperless-health-check.service
sudo systemctl start paperless-schema-check.service
docker ps --filter label=com.docker.compose.project=paperless \
  --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
sudo ss -ltnp | rg ':23238'
curl --fail http://127.0.0.1:23238/
```

Exactly five containers must run and only Paperless may publish
`127.0.0.1:23238`. The health command checks HTTP, a PostgreSQL query, Valkey,
Tika, Gotenberg, and ZFS properties without printing document data. The schema
command separately runs Django deployment checks and repairs the search index
only when required.

Before production use, upload non-sensitive French, English, and German scans
and prove full-text search. Repeat with DOCX, XLSX, PPTX, and ODT and prove both
rendering and original download. With two normal accounts, prove private
non-discovery and shared-family editing. Prove every Fastmail route's ownership,
permissions, processed-folder move, and retry behavior. Finally, verify normal
OIDC/API and native-client access without a Pangolin prompt. Verify that regular
frontend password login remains unavailable, `/admin` first requires Pangolin
authentication and then accepts the break-glass credential, and each configured
admin-path depth receives the same gate. As an ordinary document owner, prove
that share-link creation and deletion are denied. Then, as an administrator,
create a short-lived non-sensitive share, open its public /share URL in a
signed-out browser, revoke it, and prove that the URL stops working.

Configure mobile or compatible API clients with
`https://documents.shulker.link`. Generate routine API tokens from an already
authenticated OIDC profile and give clients the token, never the break-glass
username and password. The bypassed `/api/token/` endpoint still accepts local
credentials, so the break-glass password is effectively a full API
administrator credential as well as a Django recovery credential. If it is
exposed, revoke that account's tokens and rotate the password immediately. The
administrator-removal procedure revokes tokens belonging to the additional
administrator it disables.

## Backups, recovery, and upgrades

`paperless-logical-backup.timer` creates a validated PostgreSQL custom-format
dump every day and retains the newest 14 in
`/storage/flash/paperless/dumps`. Borgmatic acquires the Paperless maintenance
lock, creates a fresh logical dump, stops the stack only long enough to create
`flash_pool/flash/storage/paperless@borgmatic`, restarts and health-checks the
application, then archives
`/storage/flash/paperless/.zfs/snapshot/borgmatic`. Finish and failure hooks
destroy only this reserved snapshot; a preparation failure restarts Paperless
and removes any snapshot it created.

Before every Paperless update, run:

```sh
sudo paperless-pre-upgrade-export
sudo borgmatic create --verbosity 1
sudo borgmatic check --force
```

The exporter incrementally maintains
`/storage/flash/paperless/export/current`, includes originals, archives,
thumbnails, metadata, and settings, and records Paperless version `3.0.5`. It
does not export API tokens. `document_importer` requires the exact Paperless
version that produced the export, and client tokens must be regenerated after
that recovery path.

Recovery confidence has three levels:

1. Borg repository/archive checks pass, Paperless is healthy, and no reserved
   `@borgmatic` snapshot remains.
2. Extract an archive to a fresh disposable directory and checksum a
   representative original, PDF/A rendition, thumbnail, PostgreSQL dump, and
   search-index file.
3. Start an isolated non-public stack using the pinned versions and restored
   state; prove OCR text, search, private/family permissions, original download,
   Office rendering, and a new upload.

Never restore over the live dataset. Keep production stopped for an actual
restore, recreate only the dedicated dataset when necessary, preserve
ownership/modes/ACLs/xattrs, and validate in isolation first. Do not treat
Paperless as the sole copy of family records until several off-site archives
exist and all three recovery levels have passed.

Updates are reviewed, not automatically deployed. Compare the upstream release
and migration notes, run the portable exporter and Borg checks, update the five
compatible image tags/digests, build the generated Compose and Warden system,
then repeat OIDC, permission, OCR, Office, mail, health, and backup acceptance.
Repeat break-glass administrator recovery and public-share create, access,
expiry, and revocation tests. Scanner networking remains explicitly deferred.


## Related documentation

- [Services](Services)
- [Warden host report](Host-warden)
- [Public services](Public-Services)
- [Operations](Operations)
- [Backup and restore](Operations-Backup-and-Restore)
- [Security and recovery](Operations-Security-and-Recovery)
