# OmniRoute

OmniRoute is a private, OpenAI-compatible gateway for the owner's ChatGPT
subscription. Shulker runs one Docker container managed by NixOS, without
Compose, Redis or added request budgets. Upstream subscription quotas apply.

The dashboard is https://ai.shulker.link, protected by Pangolin's owner SSO and
OmniRoute's password. Docker publishes only `127.0.0.1:23250`. The non-root
container has a 10 GiB memory ceiling, an 8 GiB Node heap and two CPUs. It has no
host Docker socket, repository mounts or provider CLI.

## State and credentials

`/var/lib/omniroute` is writable application state, persisted under
`/nix/persist`, with owner-only permissions. It contains `storage.sqlite`, its WAL
and OAuth refresh state. OpNix injects signing, encryption and bootstrap secrets
from the OmniRoute section of the existing Shulker server item in 1Password.
Keep these secrets with a database restore; never put values in Git or chat.

Connect the native Codex/ChatGPT OAuth provider in the dashboard. This supplies
subscription authentication; OpenHands remains the coding agent. Leave paid
credits disabled and quota filtering enabled. Connect no billable API provider
and use explicit Sol/Astra model IDs without automatic paid fallback.

OpenHands on Enderdragon will use `https://ai.shulker.link/v1`, an inference key
restricted to `cx/gpt-6.1-sol` and `cx/gpt-6-astra`, and resource-scoped Pangolin
headers in native Canvas settings. Store its credentials in Enderdragon's
existing server item. Avoid unauthenticated exceptions for API paths.

Deployment startup, dashboard password authentication and anonymous inference
rejection have passed. Subscription sign-in and native OpenHands streaming/tool
calls remain acceptance steps; finding a model in the compiled image is not
proof that the subscription can run it.

## Image and updates

The published preview lacked Sol, so the installed image was built from the
unchanged upstream Dockerfile at
`61e07fb7e0d4e1e76111495d3718c9e4d06d2a62`. A small
`dashboard-translations.patch` beside this runbook restores the full
language catalog for flat dashboard routes; upstream's namespace layout otherwise
renders translation keys instead of labels. Remove the patch after an upstream
route-namespace fix passes rendered-page checks. The Shulker host pins its immutable
local image ID. A root-only compressed `docker save` archive lives in
`/var/lib/omniroute-images/omniroute-61e07fb7-labels1.tar.gz`, with a SHA-256 checksum.

An update needs a verified published digest or a new source build. For a source
build, check out an exact upstream commit and use its Dockerfile's `runner-base`
target. Apply the dashboard patch to this revision before building; the Dockerfile
itself is unchanged. The successful build used these limits and arguments:

```sh
docker buildx create --name omniroute-build --driver docker-container \
  --driver-opt memory=14g,cpu-quota=400000,cpu-period=100000
docker buildx build --builder omniroute-build --target runner-base \
  --load --provenance=false \
  --build-arg OMNIROUTE_BUILD_MEMORY_MB=8192 \
  --build-arg OMNIROUTE_BUILD_WORKERS=2 \
  --build-arg OMNIROUTE_USE_TURBOPACK=0 \
  --tag shulker/omniroute:COMMIT /path/to/checked-out/source
```

Verify compiled model support and startup using separate temporary data and a
loopback port before changing the host's image pin. Save the resulting image,
checksum it, and retain the previous image and database backup. Remove the
temporary build helper when finished. A NixOS rollback does not undo database
migrations.

## Backup and recovery

Borgmatic includes state, image archives and a consistent SQLite dump. Restore
into an empty temporary location first and check the database before replacing
live state. Restore the matching encryption secrets through OpNix. If the pinned
local image is missing, verify its archive checksum and run `docker load` before
starting the service. The Docker image itself is not rebuilt during NixOS
activation.

## Operations

```sh
sudo systemctl status docker-omniroute
sudo docker logs --tail 100 omniroute
sudo docker stats --no-stream omniroute
```

Logs can contain private prompts and responses. Inspect them locally and share
only sanitized status or error summaries.
