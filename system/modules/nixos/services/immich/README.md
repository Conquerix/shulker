# Immich

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

## Initial administrator bootstrap

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

## Health, backups, and recovery

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


## Related documentation

- [Services](https://github.com/Conquerix/shulker/wiki/Services)
- [Warden host report](https://github.com/Conquerix/shulker/wiki/Host-warden)
- [Public services](https://github.com/Conquerix/shulker/wiki/Public-Services)
- [Operations](https://github.com/Conquerix/shulker/wiki/Operations)
- [Backup and restore](https://github.com/Conquerix/shulker/wiki/Operations-Backup-and-Restore)
- [Security and recovery](https://github.com/Conquerix/shulker/wiki/Operations-Security-and-Recovery)
