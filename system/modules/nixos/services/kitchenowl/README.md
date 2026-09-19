# KitchenOwl

KitchenOwl runs on Warden as one official, digest-pinned v0.7.10 all-in-one
container with SQLite. Pangolin terminates HTTPS at `kitchen.shulker.link` and
Warden's Newt site forwards directly to `127.0.0.1:23247` (container port 8080).
The upstream image serves its web app and API through uWSGI; no additional
reverse proxy or database service is introduced. Preserve WebSocket upgrades.

## Identity and household

Use the confidential Pocket ID client restricted to intended household users.
KitchenOwl uses `client_secret_post`; this release does not send PKCE, so do not
require PKCE on this client. Register both callbacks exactly:

- `https://kitchen.shulker.link/signin/redirect`
- `kitchenowl:/signin/redirect`

Username/password login, public registration and first-admin onboarding are
all disabled. New OIDC users can still be created when Pocket ID grants access;
that group is the registration boundary. No email-domain assumption is baked
into the module. A new OIDC identity is an ordinary user, not automatically an
administrator. After the intended owner's first sign-in, use upstream
`docker exec -it kitchenowl python manage.py` to set that user as server admin.
Create one Household, owned by that user, and add other intended accounts as
members. Do not precreate an unlinked account with the same email: KitchenOwl
rejects OIDC signup when that address already belongs to another account.

Household owners control their membership. Normal users can create their own
households; this deployment does not claim an upstream switch to forbid that.
Pocket ID revocation blocks new OIDC logins but does not delete KitchenOwl
accounts or immediately revoke existing app sessions. Refresh sessions expire
after 30 days; use app-side session/account controls for immediate revocation.
Native mobile sign-in and two-device shopping-list updates need a real user
test; a healthy container or successful login redirect does not prove them.

Secrets belong to Warden's 1Password item, section `KitchenOwl`, concealed
`Environment` field, with literal multiline dotenv entries:

- `JWT_SECRET_KEY` (at least 64 hexadecimal characters)
- `OIDC_CLIENT_ID`
- `OIDC_CLIENT_SECRET`

OpNix writes root-only `kitchenowlEnv`; exact-key validation runs before a
checked rebuild. Keep these values out of Nix and Compose inspection output.
SMTP is unnecessary for Pocket ID-only login. No external LLM provider is
configured for recipe parsing.

## Storage and operation

Persist all `/data`, including `database.db` and uploaded images, under
`/storage/flash/kitchenowl/data`. Its dedicated dataset is
`flash_pool/flash/storage/kitchenowl`, quota 10 GiB, legacy mountpoint,
compression zstd, atime off, acltype posix, xattr sa and dnodesize auto. The state
guard refuses missing/wrong mounts and mismatched properties before writing.
Create the dataset before deployment. On established startup, the stopped
application receives a `before-start` snapshot before migrations run.

`kitchenowl-compose.service` owns lifecycle and uses a shared maintenance lock.
Docker's on-failure restart policy does not resurrect the container on daemon
startup before the mount guard. Health checks require the custom OIDC provider
and disabled password/registration modes, not merely an HTTP 200 response.

```sh
systemctl status kitchenowl-compose.service
kitchenowl-health-check
kitchenowl-runtime backup
kitchenowl-runtime cleanup
```

## Backup and recovery

Borgmatic briefly stops only KitchenOwl, snapshots its dataset as `borgmatic`,
and restarts it before archiving `.zfs/snapshot/borgmatic/data`. Failed snapshot
or restart steps fail the backup and attempt to recover the previously running
application. Inactive service or incorrect mounts refuse backup. Cleanup
removes only the reserved snapshot, after success or failure. The backup device
sandbox explicitly permits `/dev/zfs` without exposing other host devices.

Retrieve an archive into an empty directory, compare checksums and verify
SQLite integrity. For a full application recovery, restore the complete data
tree to a separate dataset with the matching image and saved JWT/OIDC secrets,
then test login, household membership, recipes and shopping-list updates before
switching production. Retrieval alone is not a full restore rehearsal. Reverting
the Nix generation does not reverse database migrations; preserve the snapshot
and encrypted archive before upgrades.
