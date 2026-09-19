# TaskView

TaskView provides household projects and tasks on Warden. The pinned 1.53.0
stack contains web, API, MCP, Centrifugo, PostgreSQL 17, and a one-shot migration
runner. Pangolin is the only reverse proxy; Newt connects to loopback targets.
The upstream web image uses Nginx solely to serve static application files.

## Access and identity

| Hostname | Warden target | Purpose |
| --- | --- | --- |
| `tasks.shulker.link` | `127.0.0.1:23242` | Web |
| `tasks-api.shulker.link` | `127.0.0.1:23243` | API |
| `tasks-mcp.shulker.link` | `127.0.0.1:23244` | Streamable HTTP at `/mcp` |
| `tasks-events.shulker.link` | `127.0.0.1:23245` | WebSocket at `/connection/websocket` |

Create these resources on the existing Warden Newt site in Pangolin; Nix does
not create live routes. Pangolin terminates TLS. Preserve native authentication
for API, MCP and notifications; an interactive edge login breaks these clients.
Initially restrict access to the operator until the bundled account is secured.
Verify HTTPS forwarding and WebSocket upgrades before normal access. Express
proxy trust defaults to false; set `trustProxy` only for the measured trusted
Pangolin/Newt boundary, never blindly to true.

Public registration is disabled. Use separate household identities and deliberate
project membership. The household email domain is application state, not a Nix
setting: create the household organization, add Pocket ID OIDC, and configure one SSO entry per household email domain. The operator-selected
trusted domains in the runtime secret skip the DNS/HTTP ownership proof. Register the exact
callback displayed by TaskView (API `/module/sso/callback/<config-id>`) in Pocket
ID. Trust applies only to these exact domains; `*` is unsupported. Access still
requires an allowed Pocket ID identity. Retain a secured
local recovery account and test both OIDC login and organization exclusion.

Centrifugo delivers assignment/deadline notifications while the app is open.
TaskView stores notifications in PostgreSQL. This does not provide native phone
push or guarantee live task-board refresh. Signed user-limited `personal:#id`
channels restrict each recipient. Publishing, admin, health and metrics use
private container port 9000; Pangolin reaches only client port 8000.

## Runtime secrets and email

The logical OpNix secret is `taskviewEnv`, stored in the Warden 1Password item's
dedicated TaskView Environment field. It is a multiline literal `KEY=value`
file: one field per line, no shell quoting or interpolation. Passwords containing
`$` and `#` are preserved. Do not print the input, run resolved Compose config,
or copy credentials into Nix or documentation. The checked rebuild preflight
rejects missing or empty fields before activating the configuration.

Required fields:

- `DB_PASSWORD`: PostgreSQL password, unique to this service.
- `JWT_SIGN`: random signing secret of at least 32 characters.
- `ENCRYPTION_KEY`: exactly 64 hexadecimal characters; preserve it for recovery.
- `CENTRIFUGO_API_KEY` and `CENTRIFUGO_TOKEN_SECRET`: independent random secrets,
  each at least 32 characters.
- `SMTP_HOST`, `SMTP_PORT`, `SMTP_ENCRYPTION` (`ssl` or `tls`).
- `SMTP_USERNAME`, `SMTP_PASSWORD`, `SMTP_FROM_NAME`, `SMTP_FROM_EMAIL`.
- `SSO_TRUSTED_DOMAINS`: comma-separated exact email domains approved by the
  operator for this household instance. This skips ownership proof, including
  for household members using a shared mail provider; it does not trust that
  provider as an identity issuer. Keep Pocket ID client access household-only.

Mail provider, sender and login are entirely runtime configuration. For the
approved dedicated Fastmail service account, use its full login address, an
app password, an existing allowed sender alias, host `smtp.fastmail.com`, port
465, and `ssl`. A sender alias need not equal the account login. Use the user's
designated inbox to verify invitations and password recovery before inviting
the household. No email domain or mailbox is hardcoded in the module.

The renderer writes root-only per-container files under `/run/taskview`.
Database and migration receive only the database credential. MCP receives no
shared caller credential. Updating `DB_PASSWORD` alone does not rotate an
initialized PostgreSQL role: coordinate database and secret changes explicitly.
Changing the encryption key without migrating encrypted data breaks saved SSO
configuration. Never rotate it during routine updates.

## Storage and lifecycle

State is mounted at `/storage/flash/taskview` from
`flash_pool/flash/storage/taskview`, initially capped at 20 GiB. Before the first
approved deployment, create the dataset with the declared policy:

```sh
sudo zfs create -o mountpoint=legacy -o quota=21474836480 \
  -o compression=zstd -o atime=off -o acltype=posix -o xattr=sa \
  -o dnodesize=auto flash_pool/flash/storage/taskview
```

Follow the repository's checked rebuild sequence: validate, build Warden,
review dry-activate, then approved test and switch. No reboot is needed.
Mount-source and property validation precede directory creation and backups.
PostgreSQL owns its initialized `postgres` directory; `backups` is root-only.
Container logs rotate at three 10 MiB files per component. Process crashes get
five retry attempts; Docker daemon restarts must pass the systemd mount gate.

`taskview-compose.service` waits for state, rendered secrets and pinned images.
Under the maintenance lock it stops API/MCP writers, starts a healthy database,
takes a fresh logical dump, runs migrations, and starts the application only
if migration succeeds. On failure, inspect the unit and fix the cause; do not
start API or MCP manually around the migration gate. Use the systemd lifecycle
for normal starts/stops. `taskview-compose` is the low-level operator wrapper.

```sh
sudo systemctl status taskview-compose.service --no-pager
sudo journalctl -u taskview-compose.service --since today
sudo taskview-health-check
sudo taskview-backup-prepare
```

The health timer checks every 15 minutes and does not restart services. Health
proves container readiness, not household login, mail delivery, or MCP access.
Review upstream changes and update compatible images together in `images.nix`.
Do not automatically roll back database schemas when reverting a Nix generation.

## Backups and recovery

Borgmatic creates a fresh custom-format PostgreSQL dump before each archive.
Only after `pg_restore --list` succeeds is the dump set atomically published,
with catalogue, SHA-256 checksum, timestamp and image manifest. Fourteen local
sets are retained. The shared maintenance lock serializes startup and backups;
a failed fresh dump aborts Borg archive creation even if older dumps exist.
Routine logical backups do not stop the application. Live PGDATA is not the
portable recovery artifact; all application data is in PostgreSQL in this release.

Preserve the runtime credentials, especially the original encryption key, in
1Password. Retrieve one completed dump set into a new empty temporary directory
and verify `sha256sum -c SHA256SUMS` plus `pg_restore --list taskview.dump`.
That is a retrieval check, not a full restore rehearsal.

For recovery, use an isolated PostgreSQL 17 instance with role/database
`taskview`, matching image versions from the manifest, and original runtime
secrets. Import into an empty database:

```sh
pg_restore --exit-on-error --username taskview --dbname taskview taskview.dump
```

Start the matching TaskView images against that isolated database. Verify login,
organization/project permissions, representative tasks and notification history
before any route change. Never restore over production automatically. If an
upgrade needs rollback, preserve both the current dataset and pre-upgrade dump;
restore the old version into an isolated target under an approved recovery plan.

## Codex and Hermes MCP

Release 1.53.0 uses TaskView bearer API tokens for remote MCP; it does not implement
MCP OAuth. Create separate tokens for Codex and Hermes, scoped to approved projects
and operations. Grant only needed permissions. Neither client should use the
household administrator's session token.

Codex personal configuration:

```toml
[mcp_servers.taskview]
url = "https://tasks-mcp.shulker.link/mcp"
bearer_token_env_var = "TASKVIEW_CODEX_TOKEN"
```

The actual Codex desktop process must receive that protected variable. Do not
put the token in tracked configuration. If the desktop launch environment does
not supply it, configure a supported credential helper after checking the
installed Codex version.

Merge this entry into Hermes's existing mutable configuration on Shulker:

```yaml
mcp_servers:
  taskview:
    url: https://tasks-mcp.shulker.link/mcp
    headers:
      Authorization: "Bearer ${TASKVIEW_HERMES_TOKEN}"
```

Supply `TASKVIEW_HERMES_TOKEN` to both `hermesAgentEnv` and `hermesWebUiEnv`;
both containers execute tools. Preserve existing fields and MCP entries. During
credential activation, preserve currently running image IDs: the existing
Hermes pull-always/latest policy must not turn this into an unrelated upgrade.

## Acceptance and rollback

After approved setup, verify Pocket ID login, local recovery, denied access
for unrelated identities, invitations and password recovery. Use two household
accounts to check assignment/deadline notifications without page reload,
wrong-recipient denial, and reconnection after a notification transport restart.
Check that public publishing/admin/health endpoints are absent.

For each MCP client, read/create/update/complete a disposable task, verify an
excluded project is denied, and test independent token revocation. Also test an
invalid nonempty token against an actual data operation: MCP initialization or
tool listing alone does not authenticate to the API. Exercise both Hermes
Telegram and WebUI. Record these runtime results separately from Nix checks.

Before accepting household data, rollback can disable just the TaskView routes
and units, retaining its dataset and backup history. Never remove shared DNS,
unrelated Pocket ID clients, mail credentials or existing Borg archives.
