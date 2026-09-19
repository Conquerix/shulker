# Actual Budget

Actual Budget runs on Warden as one official, digest-pinned 26.9.0 container.
Pangolin terminates HTTPS at `budget.shulker.link`, forwarding through Warden's
Newt site to `127.0.0.1:23246`. The container listens on port 5006; no public
host listener or additional reverse proxy is configured.

## Identity and first sign-in

Use a confidential Pocket ID client with PKCE and the callback
`https://budget.shulker.link/openid/callback`. Restrict its allowed group to the
intended owner before exposing the route. The first successful OpenID login
becomes Actual's server owner; leave this sign-in to the intended user.
Actual enforces OpenID, permits additional users only after manual creation,
and expires server sessions after 30 days. Adding a Pocket ID group member
does not itself create an Actual user. Match Actual usernames to the provider
identity, then explicitly share each intended budget in Actual.

The OIDC client settings are runtime secrets in Warden's 1Password item,
section `Actual Budget`, field `Environment`, as literal multiline values:

- `ACTUAL_OPENID_CLIENT_ID`
- `ACTUAL_OPENID_CLIENT_SECRET`

OpNix materializes the root-only `actualBudgetEnv` secret. Values never belong
in Nix, generated documentation, or resolved Compose output. No SMTP is needed.
There is no shared application password login while OpenID is enforced.
Keep infrastructure/Pocket ID recovery access available independently.

The version-specific startup guard makes OIDC initialization failure fatal
before the HTTP listener opens. Upstream 26.9.0 otherwise keeps running with
fresh password setup available after discovery failure. The guard checks the
exact pinned startup block and refuses changed code; review it when upgrading.

At the public URL verify exactly one `Cross-Origin-Opener-Policy: same-origin`
and `Cross-Origin-Embedder-Policy: require-corp`; Actual serves these itself.
Check browser `crossOriginIsolated` and complete a real Pocket ID sign-in.
Neither successful health checks nor an authorization redirect proves the
complete login and budget-sync flow.

## Storage and lifecycle

Persist the entire `/data` tree at `/storage/flash/actual-budget/data`, including
server-files and user-files. The dedicated legacy-mounted ZFS dataset is
`flash_pool/flash/storage/actual-budget`, quota 10 GiB, compression zstd, atime
off, acltype posix, xattr sa, dnodesize auto. A missing or incorrect mount/quota
prevents startup and backups. Create this dataset before checked deployment.

`actual-budget-compose.service` owns container lifecycle. Docker does not
automatically resurrect containers on daemon startup before the mount check.
Startup, shutdown and backup operations share a maintenance lock. Before an
existing data tree starts, the stopped application gets a `before-start`
snapshot. This retains one immediate pre-start recovery point. Schema changes
belong to the application; reverting a Nix generation does not revert data.

Useful commands:

```sh
systemctl status actual-budget-compose.service
actual-budget-health-check
actual-budget-runtime backup
actual-budget-runtime cleanup
```

Do not invoke raw Compose to bypass the systemd lifecycle or maintenance lock.

## Backup and recovery

Before Borgmatic create, stop only Actual briefly, create the reserved
`borgmatic` ZFS snapshot, and restart Actual before archiving. Borg reads
`.zfs/snapshot/borgmatic/data`; it does not copy live SQLite files. Failed
snapshot or restart operations fail the backup, attempt to recover the stopped
application and remove a failed snapshot. Borg cleanup removes the reserved
snapshot after success or failure. Other applications are not stopped by this
hook. An inactive Actual container causes backup failure instead of silently
reusing an old snapshot.

Extract the archived data into an empty temporary directory, verify SQLite
integrity and file checksums, and preserve the image version and OIDC secret.
For application recovery, use a separate dataset and matching container image
against the extracted complete data tree. Verify login and representative
budget contents/sync before switching production. Never overwrite live data
or assume retrieval alone is an application restore test.

Bank connections are not configured. Budget end-to-end encryption is optional
and chosen by the user; its password is separate from Pocket ID and must have
an independent recovery copy. The server alone cannot recover encrypted
budgets without that password. Users should also retain budget exports.
