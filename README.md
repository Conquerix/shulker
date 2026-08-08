# Shulker

Personal, flake-based Nix configuration for NixOS and nix-darwin. It manages
hosts, reusable system profiles and services, Home Manager configuration, and
1Password-backed secrets.

This repository is tailored to Conquerix's machines. Treat it as a reference,
not a drop-in configuration.

## Layout

- `system/hosts/` contains the machine-specific NixOS and Darwin entry points.
- `system/profiles/` groups reusable desktop, server, Steam Machine, and MacBook
  behavior.
- `system/modules/` contains reusable services and platform configuration.
- `system/users/` connects system users to their Home Manager configuration.
- `home/` contains shared Home Manager modules and defaults.
- `lib/`, `overlays/`, and `nix/` contain flake helpers, package overrides, and
  compatibility configuration.
- `.github/` contains validation, dependency-maintenance, and Wiki automation.

The flake discovers host directories automatically. Each host imports its
hardware configuration and enables only the profiles and modules it needs.

## Hosts

NixOS: `enderdragon`, `endermite`, `guardian`, `phantom`, `shulker`,
`silverfish`, `warden`, and `wither`.

Darwin: `herobrine`.

The [server documentation guide](system/hosts/nixos/README.md) explains how to
build per-host Markdown reports from the evaluated NixOS configurations.

## Host documentation

Build detailed reports for every NixOS and nix-darwin host into `result/`:

```sh
nix build .#host-docs
```

Each machine has a dedicated `host-docs-<host>` target. NixOS reports include
enabled roles and services, network exposure, containers, storage, persistence,
backup coverage, secret names, operational warnings, and deployment commands.
nix-darwin reports cover roles, users, security, packages, Homebrew, launchd,
and operations. Secret values and references are excluded. The existing
`server-docs` and `server-docs-<host>` targets remain compatibility aliases for
server-profile hosts.

Do not edit generated Markdown. Change the host or module configuration, or
extend the relevant generator, then rebuild the target. Newly discovered NixOS
and nix-darwin hosts automatically receive a report and appear in the Wiki.

## Infrastructure topology

Build the machine-readable infrastructure inventory and the Wiki-ready Mermaid
diagram from evaluated configuration:

```sh
nix build .#infrastructure-data
nix build .#infrastructure-diagram
nix build .#wiki-docs
ls result/{Infrastructure.md,infrastructure.json}
```

The diagram covers all NixOS and nix-darwin hosts, enabled services, and known
cross-service connections. `topology/public.json` is the sanitized boundary for
data that exists only in external control planes. The Pangolin collector updates
that snapshot with public resources and their site relationships:

```sh
PANGOLIN_API_ENDPOINT=https://api.example.com \
PANGOLIN_ORG_ID=example \
PANGOLIN_API_KEY=... \
scripts/fetch-pangolin-topology.sh
```

Use a read-only organization key. The collector deliberately excludes internal
target addresses, ports, private resources, access policies, identities, and
credentials. Detailed external snapshots must remain in ignored
`topology/private*.json` files and must not be published to the repository or
Wiki.

`wiki-docs` builds the complete navigable Wiki layer: overview, fleet, server
index, service catalog, public-service inventory, split topology diagrams,
operations guide, automation guide, sidebar, and footer. Detailed per-server
reports are supplied by `host-docs` and merged by the Wiki workflow.

On a self-hosted Pangolin control plane, enable and expose the Integration API
with the root-only, reversible bootstrap helper. It preserves the existing YAML,
creates root-only backups, validates the edited files, and rolls back if the
Pangolin API does not become healthy:

```sh
sudo nix shell nixpkgs#yq-go --command \
  scripts/configure-pangolin-integration-api.sh api.example.com
```

The helper briefly restarts Pangolin and Traefik. Create the collector key in
**Organization → API Keys** with only `listSites`, `listResources`,
`listTargets`, and `listOrgDomains`; then store it as the GitHub Actions secret
documented in [the automation guide](.github/README.md#pangolin-topology-enrichment).

## Hermes WebUI and native clients

Shulker runs the community
[Hermes WebUI](https://github.com/nesquena/hermes-webui) beside the existing
Hermes Agent gateway. The containers share Hermes state and workspace data; the
running Agent source is refreshed into an ephemeral, read-only WebUI mount on
each start. This follows the upstream two-container deployment without leaving
a stale named source volume after image updates. Browser-triggered tools execute
inside the WebUI container, while Telegram-triggered work continues in the
Hermes Agent container.

WebUI is published only on host loopback at `127.0.0.1:23234`. Pangolin should
expose that target as `https://hermes.shulker.link`. Do not open the port in the
host firewall or publish WebUI without its native authentication.

Create a `WebUI Environment` field in Shulker's existing Hermes 1Password item
containing:

```dotenv
HERMES_WEBUI_PASSWORD=<strong unique password>
```

After the secret exists, deploy the NixOS configuration and create a Pangolin
HTTP resource pointing to `http://127.0.0.1:23234`. Verify the service locally
before configuring a client:

```sh
curl --fail http://127.0.0.1:23234/health
```

For [Hermes Agent for macOS](https://github.com/hermes-webui/hermes-swift-mac),
select **Direct** connection mode and set the target URL to
`https://hermes.shulker.link`. The iOS client connects to the same WebUI service.
The browser interface is also installable directly as a PWA.

## GrapheneOS WebDAV backups

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

## OpenCloud family storage

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

## Immich family photos

Warden runs [Immich](https://docs.immich.app/) as the family's authoritative
photo and video library. The NixOS module follows Immich's official Compose
topology: Immich server, the OpenVINO machine-learning service, Valkey, and
PostgreSQL 14 with VectorChord. The current release is `v3.1.0`; every image is
pinned by both tag and immutable digest in the evaluated configuration. Updates
are reviewed and deployed manually as one coupled stack.

Immich listens only on `127.0.0.1:23237`. Pangolin is the sole public path at
`https://photos.shulker.link`; keep the host firewall closed, preserve the
original Host header, and do not add a second Pangolin authentication layer
because the native clients need direct access to Immich's API and OIDC routes.

All persistent state lives in `flash_pool/flash/storage/immich`, mounted at
`/storage/flash/immich` with a 1.5 TiB quota. Before the first deployment,
create and temporarily mount the empty dataset:

```sh
sudo zfs create \
  -o mountpoint=legacy \
  -o quota=1.5T \
  -o compression=zstd \
  -o atime=off \
  -o acltype=posixacl \
  -o xattr=sa \
  -o dnodesize=auto \
  flash_pool/flash/storage/immich
sudo install -d -m 0750 /storage/flash/immich
sudo mount -t zfs \
  flash_pool/flash/storage/immich /storage/flash/immich
```

The NixOS mount unit and `immich-state.service` take over after deployment.
Immich manages `/storage/flash/immich/library`; never edit that tree directly,
add an external library pointing at it, or enable storage templates. PostgreSQL
state and the OpenVINO model cache share the dataset so one snapshot represents
the whole application.

Create an `Immich` section with an `Environment` field in Warden's existing
item in the Shulker 1Password vault. Store a dotenv document with exactly these
keys and their real values:

- `DB_PASSWORD`: a strong, unique alphanumeric database password;
- `OAUTH_CLIENT_ID`: the client identifier issued by Pocket ID;
- `OAUTH_CLIENT_SECRET`: the confidential client secret issued by Pocket ID.

The checked rebuild validates the logical `immichEnv` secret before evaluating
a deployment. OAuth configuration is rendered root-only under `/run`; secret
values do not enter the Nix store or generated documentation.

In Pocket ID, create these groups and claims:

| Group | Claim key | Claim value |
| --- | --- | --- |
| `immich_admins` | `immich_role` | `admin` |
| `immich_users` | `immich_role` | `user` |

Add the owner's Pocket ID account to `immich_admins` and family accounts to
`immich_users`. Create one confidential authorization-code OIDC client,
restricted to those groups, with these redirect URIs:

```text
app.immich:///oauth-callback
https://photos.shulker.link/auth/login
https://photos.shulker.link/user-settings
```

Configure its back-channel logout URL as:

```text
https://photos.shulker.link/api/oauth/backchannel-logout
```

Pocket ID is the only ongoing login method. Immich automatically registers
allowed users, launches OAuth from the login page, maps `immich_role`, and has
no default per-user quota. Password login remains disabled.

### Initial administrator bootstrap

Warden normally keeps `allowSetup = false`. Temporarily change it to `true`
only while bootstrapping a new instance, and keep that instance private during
this one-time sequence:

1. Create the dataset, Pocket ID objects, and 1Password field.
2. Deploy Immich without creating its Pangolin resource.
3. Open a temporary Mac tunnel with
   `ssh -o ForwardAgent=yes -L 23237:127.0.0.1:23237 warden.ssh`.
4. Visit `http://127.0.0.1:23237` and create the first administrator with the
   exact email address used by the owner's Pocket ID account.
5. Create the public Pangolin resource for `photos.shulker.link`, then sign in
   through Pocket ID so Immich links the account by email and applies `admin`.
6. Change Warden to `allowSetup = false`, commit, push, and deploy again.

The one-time bootstrap password does not become an ongoing login method. Never
leave `allowSetup = true` after the Pocket ID administrator is verified.

### Health, backups, and recovery

Deployments pull all digest-pinned images through the separately bounded
`immich-image-pull.service` before starting Compose. Image download has a
30-minute limit; after it succeeds, `immich-compose.service` retains its
separate five-minute container-health limit.

Verify the local service before and after publishing it:

```sh
sudo systemctl status immich-compose.service --no-pager
sudo systemctl start immich-health-check.service
sudo systemctl start immich-schema-check.service
docker ps --filter label=com.docker.compose.project=immich \
  --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
curl --fail http://127.0.0.1:23237/api/server/ping
```

The server declaratively selects the Intel Arc A380 at `/dev/dri/renderD128`
through Quick Sync for supported video work; accelerated decode is enabled and
machine learning uses OpenVINO. Acceptance requires a real transcode plus real
facial-recognition and smart-search jobs, not only `/dev/dri` visibility or the
configured backend.

Immich creates a compressed database dump every day and keeps 14 copies inside
the library. This is secondary protection, not a complete backup. Warden's
Borgmatic job stops the four-container stack, creates
`flash_pool/flash/storage/immich@borgmatic`, immediately restarts and health
checks Immich, then archives
`/storage/flash/immich/.zfs/snapshot/borgmatic`. Success and failure cleanup
destroy only that reserved snapshot.

For recovery, keep production stopped and extract
`storage/flash/immich/.zfs/snapshot/borgmatic` from Borg into an empty disposable
directory first. Inspect the archive, recreate the dataset with the properties
above when needed, restore the complete `library`, `postgres`, and `model-cache`
trees with ownership, modes, ACLs, and xattrs preserved, and start the exact
Immich release compatible with the archive. Run `immich-admin schema-check` and
validate an original photo, video, thumbnails, facial recognition, smart
search, and a new upload in an isolated restore rehearsal before relying on the
archive as a recovery point.

Configure the Immich mobile client with `https://photos.shulker.link`. Before an
upgrade, read the matching upstream release and breaking-change notes, update
mobile clients when required, confirm a recent off-host archive and database
dump, compare the release's Compose and hardware-acceleration files, resolve
Linux/amd64 image digests with `skopeo`, and update all four pins together.
Repeat OAuth, upload, accelerator, and backup acceptance afterward. GitHub may
propose dependency changes, but no workflow deploys Immich automatically.

## Paperless family documents

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

### Storage and secrets

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

### Pocket ID-only login and bootstrap

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
Pocket ID. Never use `createsuperuser` or assign a Paperless password.

OIDC needs the production callback during initial provisioning. Create the
Pangolin resource before the first login, but initially protect the entire
resource with Pangolin authentication and grant access only to the owner. Then:

```sh
sudo paperless-bootstrap-groups
# Sign in once through Pangolin and Pocket ID before continuing.
sudo paperless-list-users
sudo paperless-promote-oidc-admin USERNAME
sudo paperless-list-users
```

Pass the exact OIDC username reported by `paperless-list-users`. Promotion
refuses any account with a usable password. Configure the internal application
through this OIDC administrator, verify permissions and ingestion privately,
then replace the temporary Pangolin authentication gate with the final policy.

The final Pangolin rules are ordered as follows:

1. deny the exact `/admin` path;
2. deny every `/admin/*` descendant;
3. deny the exact `/share` path;
4. deny every `/share/*` descendant;
5. forward every other path to `http://127.0.0.1:23238` without Pangolin
   authentication.

Paperless itself remains the authentication layer for web, API, media, static,
and OIDC callback traffic. Do not add a second login gate after bootstrap,
because mobile/API clients and the OIDC redirect flow need direct application
access. Public share links remain disabled in practice and in permissions;
enabling them later requires reviewing both Paperless permissions and the two
Pangolin share-path denials.

To remove an administrator, first revoke active Paperless authority locally,
then remove Pocket ID access:

```sh
sudo paperless-revoke-admin USERNAME
# Use --disable-user only when the internal account must also be deactivated.
sudo paperless-revoke-admin --disable-user USERNAME
```

The command terminates that user's sessions, revokes API tokens, removes the
administrator group, and clears staff/superuser flags. Only after it succeeds
should the user be removed from the Pocket ID group or client allowlist.

### Permissions and intake

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
| `name` | Unique lowercase route identifier using letters, digits, and hyphens |
| `address` | Exact Fastmail alias or plus-addressed recipient |
| `owner` | Exact username reported by `paperless-list-users` |
| `scope` | `private` or `family`; exactly one route is `family` |

Apply the routes without exposing credentials:

```sh
sudo paperless-bootstrap-fastmail \
  --admin-username USERNAME \
  --routes-json /run/paperless-fastmail-routes.json
sudo rm -f /run/paperless-fastmail-routes.json
```

The idempotent command upserts only `Fastmail Paperless` and rules prefixed
`Shulker route - `. It accepts attachments, applies the global
`Source: Fastmail` tag, assigns the route owner, moves successfully processed
mail to `Paperless/Processed`, and removes only obsolete rules carrying its own
prefix. Failed processing remains visible in Paperless task history and the
source mailbox.

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

### Health and acceptance

Image pulling has a separate 30-minute unit; Compose startup has a five-minute
health limit. Verify the local stack before changing Pangolin:

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
OIDC/API access alongside public denial of regular login, `/admin`, and
`/share`.

Configure mobile or compatible API clients with
`https://documents.shulker.link`. API tokens are created only from an already
authenticated OIDC profile and are revoked by the administrator-removal
procedure.

### Backups, recovery, and upgrades

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
Scanner networking and public share links remain explicitly deferred decisions.

## Development and validation

Use the smallest relevant check while iterating, then validate in proportion to
the change:

```sh
# Evaluate every exported configuration and check.
nix flake check --no-build --all-systems

# Run the full flake checks, including build-backed checks.
nix flake check

# Build all host reports or one host report.
nix build .#host-docs
nix build .#host-docs-<host>

# Build the generated infrastructure topology.
nix build .#infrastructure-diagram

# Build every generated non-host Wiki page.
nix build .#wiki-docs

# Format the Nix sources.
nix fmt

# Enter the development shell with repository checks installed.
nix develop

# Check every prospective 1Password secret, then apply a NixOS configuration.
sudo nix run .#checked-rebuild -- switch --flake .#<host>

# Once the wrapper is installed by a deployment, the shorter form is available.
sudo shulker-rebuild switch --flake .#<host>

# Apply the Darwin configuration.
darwin-rebuild switch --flake .#herobrine
```

Track newly created Nix files before evaluating the flake because Git flakes
omit untracked files. Pre-commit hooks and `nixfmt` may modify files during a
commit; review and stage those changes before retrying.

## Maintenance conventions

- The default branch is `dev`.
- Inspect the relevant host, profile, and module before changing behavior.
- Preserve unrelated working-tree and staged changes. Keep commits focused on
  one task and use imperative Conventional Commit-style subjects.
- Verify critical behavior from evaluated or runtime state when possible, not
  only from source diffs.
- Do not amend published commits, force-push, or rewrite shared history without
  explicit agreement.
- Keep GitHub Actions pinned to full commit hashes and retain the release tag in
  a comment.

## Security and recovery

The NixOS configurations expect an opnix service-account token at
`/etc/opnix-token`. Secret values remain outside this repository.

Use `shulker-rebuild` for NixOS deployments. Before calling `nixos-rebuild`, it
evaluates the requested host from the prospective flake, reads the configured
token path, and asks OpNix to resolve every configured secret reference. The
resolved values exist only in a private temporary directory which is removed
before the rebuild begins. Failures report logical secret names, never values
or 1Password references. The first deployment can run the same wrapper with
`sudo nix run .#checked-rebuild -- ...`.

Rollbacks do not need this check. If 1Password is unavailable during an
emergency but the currently provisioned secrets are known to be usable, pass
`--skip-secret-check` explicitly. This is a recovery escape hatch; routine
deployments should remain fail-closed.

Local login password hashes are declared in the NixOS user configurations.
Users are immutable, so every activation restores the declared password. To
rotate a password, generate a yescrypt hash and replace the corresponding
`hashedPassword` value before rebuilding:

```sh
nix shell nixpkgs#mkpasswd --command mkpasswd -m yescrypt
```

This intentionally exposes the hashes through Git history and the Nix store,
allowing offline password cracking attempts. Use strong, unique passwords.
SSH password authentication remains disabled: the passwords provide console
and sudo access, while the configured keys provide key-only `conquerix` and
root recovery access.

### Touch ID-backed remote sudo

The macOS SSH client uses the 1Password SSH agent and forwards it only to
Pangolin SSH resources matching `*.ssh`. NixOS hosts accept an agent signature
for `sudo` and `sudo -i` when it matches a key in the root-owned
`/etc/ssh/authorized_keys.d/<user>` file. The private key and Touch ID data stay
on the Mac; password-based sudo remains available when the agent is absent or
locked.

In 1Password for Mac, enable **Settings -> Developer -> Use the SSH Agent** and
Touch ID. For tighter approval scope, configure the agent to ask for each new
application and terminal session and avoid **Approve for all applications**.
1Password may reuse an approval within the configured agent session, just as
sudo caches a successful authentication for a short period.

After applying the Darwin configuration and deploying a NixOS host, verify the
effective client policy and then force a fresh sudo authentication:

```sh
ssh -G warden.ssh | grep '^forwardagent yes$'
ssh warden
test -S "$SSH_AUTH_SOCK"
ssh-add -l
sudo -k
sudo true
```

Agent forwarding gives processes running as the connected remote user access
to the forwarded socket for the lifetime of that SSH session. Keep it scoped to
trusted hosts, close sessions when finished, and retain the independent console
password and root recovery keys.

Keep `users.mutableUsers = false`, the declarative password hashes, and the
independent SSH recovery keys unless deliberately changing the recovery model.
Generated documentation and diagnostic output must not expose secret values,
secret references, generated secret paths, password hashes, or service
credentials.

## Operational safety

Deployments, reboots, credential changes, destructive storage or database work,
and Git history rewrites can affect live systems or recovery. Confirm their
scope before running them.

Before restarting a gaming host or session, check for an active game and do not
interrupt it:

```sh
pgrep -f 'steamapps/[c]ommon'
```

## Backup verification and restoration

Borgmatic performs weekly repository checks and monthly archive checks. Test
the repository and inspect its archives manually after changing backup
configuration:

```sh
sudo borgmatic check --force
sudo borgmatic repo-list
```

Immich's snapshot hooks run inside Borgmatic's private device namespace. The
unit binds and permits only `/dev/zfs`, with `CAP_SYS_ADMIN` retained solely so
ZFS can create and destroy the guarded snapshot; do not disable the broader
device sandbox to make ZFS visible.

The backup module pins Hetzner Storage Box's published ED25519 host key in the
system-wide SSH known-hosts file. Keep that trust root declarative: verify any
future key change against Hetzner's independently published fingerprint before
updating the pin, rather than accepting a key interactively.

Borg authenticates with the host's persistent ED25519 key. After OpNix
provisions that private key, `sshd-keygen` and every SSH daemon start
atomically regenerate its adjacent public key; this prevents OpenSSH from
offering a stale `.pub` file during backup authentication.

Test file restoration into an empty temporary directory rather than over the
live filesystem:

```sh
restore_dir="$(mktemp -d)"
sudo borgmatic extract --archive latest --destination "$restore_dir" --path path/to/file
```

Database restoration is a separate, destructive operation. Use `borgmatic
restore --archive latest` only after validating the extracted backup and the
target database service.

## Repository automation

GitHub Actions validate every push and pull request, retain generated reports
as workflow artifacts, propose weekly flake-input updates, and publish the
host reports to the [repository Wiki](https://github.com/Conquerix/shulker/wiki).
Dependabot groups updates to pinned GitHub Actions into weekly pull requests.

See the [automation guide](.github/README.md) for workflow triggers,
permissions, and Wiki synchronization behavior.

## Origins

Originally forked from EmergentMind's
[nix-config](https://github.com/EmergentMind/nix-config) and since adapted to
this host and module layout.
