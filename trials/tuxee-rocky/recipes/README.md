# Locked-source reconstruction and qualification

## Status and boundaries

This is an **exercised trial recipe collection**, not a turnkey reproducible
release image. Source archives and observed tool binaries are locked; RPM
versions are inventoried, but the runtime Containerfile still resolves moving
UBI repositories. A clean-room complete rebuild has not been rerun from these
published files. Do not describe it as bit-for-bit reproducible or production
ready. No Docker daemon is used: `Dockerfile` is consumed by Podman.

Actual results are retained under `../evidence/`. Core kind/Tilt, native Tuxee
PAM/files/terminal/logout/reconnect/SSH, and a minimal real X11 keyboard/display
probe passed. The earlier core evidence's `gui_not_running` row is historical
and superseded by separate GUI evidence, not silently rewritten.

## Guest and nested runtime

Use only the disposable Rocky guest from `../harness.nix`. The final intended
project is not VM-based. Guest packages: Podman, fuse-overlayfs, slirp4netns,
git, curl, tar; guest SELinux remains Enforcing. Effective rootless nesting
required explicit guest-only linger for trial UID1000 and this drop-in:

```ini
# /etc/systemd/system/user@1000.service.d/90-tuxee-trial.conf
[Service]
Delegate=cpu cpuset io memory pids
```

Guest daemon-reload/user-manager restart interrupts owned guest containers;
perform it only during initial fixture setup, never while inspecting retained
baseline. Verify actual cgroup subtree controllers, not just configuration.
The successful diagnostic outer launch was rootless guest Podman with
`--privileged --systemd=always -v "$HOME/tuxee-trial/workspace:/workspace:Z"`,
container name `tuxee-nested`. This turns off container SELinux label isolation
and is **not restricted-security acceptance**. No physical-host settings,
Docker engine or host engine socket are required or authorized by this recipe.
`Containerfile.runtime` is the actual initial successful image recipe.

Inside it, use kind0.31.0 and node1.35.0 with `../workspace/kind.yaml`:

```sh
KIND_EXPERIMENTAL_PROVIDER=podman kind create cluster --name tuxee-trial \
  --image kindest/node:v1.35.0@sha256:986401fce0e567a9860075ba9df8c8459bd99a35f79024d8a682773fb40f0753 \
  --config /workspace/kind.yaml
kubectl wait --for=condition=Ready nodes --all --timeout=180s
```

Copy the workspace fixture files into `/workspace`, create `app/message.txt`
containing `tuxee-tilt-before`, then run Tilt using its native Podman custom
build. `build.sh` deliberately removes only its generated archive before save,
uses explicit `localhost/` refs and imports with version-specific containerd
`ctr --local` plus fuse-overlayfs. Tilt Docker pruning is disabled. Acceptance:
HTTP18080/message.txt before, edit only that source file to `tuxee-tilt-after`,
wait for actual Tilt sync, assert HTTP after and identical pod UID/container ID.
Published historical evidence records both identities; `../preservation.sh`
rechecks retained runtime without changing source or restarting anything.

## Tuxee native build

Pinned upstream `https://github.com/agent0ai/tuxee.git` commit
`ee6192f5265ef5a75340629aa4f79bfa1490d481`; Node/npm with package-lock SHA256
`8d0b495a56b7e616334f1ce419cdc9e6fef75d78a7002513a0ec90d10ea122eb`.
Run `npm ci --ignore-scripts && npm run build` in a clean `source/` checkout.
Go used was1.27.3. `prepare-sysroot.py` verifies exact official UBI URLs/hashes
from `packages.json`; it needs local libarchive and a clean private sysroot.
It is not a signature verifier/general-purpose untrusted RPM extractor.
Linux-PAM headers only: upstream v1.5.1 commit
`225f17470eed9f44282f435ad1ed64c94d9a2ddf` in `pam-source/`; runtime PAM stays UBI.
Musl1.2.5 mirror commit `0784374d561435f7c787a555aeab8ede699ed298` from
`https://github.com/ifduyue/musl.git` was used because official endpoints timed
out. Mirror provenance remains a redistribution review item.

Build musl into private `toolchain/`; `musl-static-pie-cc` explicitly links
rcrt1 static PIE (naive upstream musl GCC specs leave PT_INTERP with -static-pie).
Use that wrapper for source/internal/keeper's guardian build. Require `readelf`
no PT_INTERP and actual `keeper-smoke.py` protocol success. Run backend build:

```sh
# From source/, substitute absolute recipe directory and Go executable.
CGO_ENABLED=1 CC="$RECIPE/ubi9-cc" GOMAXPROCS=4 go build -trimpath \
  -ldflags='-s -w -X main.version=0.0.0-ubi9-prep' -o ../tuxee-ubi9 ./cmd/tuxee
```

Require maximum GLIBC2.34 and actual UBI loader startup. Observed binary hash
`9e0e0ef503b9bdb3885c2635451a6bc5435a218195f9e7ac3fed3b201117b112`
is an artifact identity, not a promised deterministic rebuild hash.

## GUI source builder

`fetch-locked.py` downloads existing `gui-source-lock.json` without regenerating
it from moving Debian indexes. These are **source archives**, never Debian,
Rocky or EPEL binary RPMs. Copy archive files plus lock into `/trial/gui` in a
separate UBI9 builder, with `/workspace/tuxee-runtime:/trial` mounted. Observed
builder base: `registry.access.redhat.com/ubi9/ubi-minimal@sha256:312b02a8f8ad5bdd219849c3e854cc5191c92fb7b8ce9b30fe2daed2de849094`.
Install only official UBI development tools and libraries: gcc/g++, make,
cmake, autoconf/automake/libtool, pkgconf, patch, tar/xz/gzip, Python3,
X11/Xrender/xorgproto, freetype/fontconfig/glib2/xml2, zlib/jpeg/png,
OpenSSL-devel, xkeyboard-config, dbus-daemon, meson/ninja from CodeReady.
The exact observed full package set is `../evidence/builder-rpm-inventory.txt`.
PAM development RPM is unavailable: copy pinned Linux-PAM headers under
`/usr/include/security` and create builder-only libpam.so linker symlink to
UBI libpam.so.0. Do not replace PAM runtime/configuration.

`python3 /trial/gui-build.py` expects `/trial/gui` and installs into
`/opt/tuxee-gui` **inside the builder**. It unpacks trusted hash-verified sources
and runs upstream build systems; never run it on the physical host. Preserves
TigerVNC1.16.2/Xorg21.1.25 and upstream xserver21.patch. PAM is required despite
TigerVNC's ineffective ENABLE_PAM=OFF flag. It builds reduced X11+Matchbox,
not xterm/GTK/Electron/browser/audio/GPU. Compile `gui-test-app.c` with Xlib as
`/opt/tuxee-gui/bin/tuxee-gui-probe`. Stage dependencies privately under
`/opt/tuxee-gui/deps` (do not overwrite system libc/libraries), retain XKB data
and original licenses, then use `gui-install-wrappers.py` in the owned runtime.
The original private export script copied wider library paths; do **not** use
that intermediate archive as a general-purpose runtime installation method.
No complete clean-room staging driver or distribution/legal review is claimed.

## Actual acceptance drivers

Copy the drivers to owned `/workspace/tuxee-runtime` inside `tuxee-nested`:

1. `runtime-accept.py`: **first-run fixture**; creates scoped tuxeeaccept,
   memory-only password, loopback18443 server, terminal/file/SSH and native
   session tests. It is intentionally not idempotent (SSH key already exists
   on rerun); do not rerun against retained evidence or real accounts.
2. `gui-accept.py`: fresh GUI terminal, actual RFB over authenticated Tuxee WS,
   keyboard input, independent UID1000 file, title/framebuffer change.
3. `restart-accept.py`: proposed graceful server SIGTERM/relaunch test preserving
   guardian shell PID and file, then actual authenticated WS input/output.
   **Not executed: tool approval pending. Do not count it as a passed test.**

Fixture password rotation is confined to its disposable account. No secrets
are committed. Runtime/server/terminal/GUI logs and state stay in guest-owned
workspace; fixtures remain for independent readback. VM/container recovery,
crash recovery, full reproducible image, owner browser UX, representative GUI,
VS Code Remote SSH UI and actual authorized agent inference remain open.

## Read-only repository inventory

`python3 ../inventory.py /workspace` emits repository HEAD/branch/dirty flag,
sanitized remotes and linked worktree paths. No fetch, repo hooks, fsmonitor,
optional Git locks or file-content reads. Local tests use real repositories,
linked worktrees, dirty files and credential-bearing synthetic remotes.
Actual guest discovery is saved separately in evidence; it found a genuine
source-repository checkout, not an invented task project. This CLI is **not**
a Tuxee-integrated dashboard or agent control plane. Don't expose it as an
unauthenticated HTTP endpoint; review output before wider publication.

## Teardown

Retain artifacts until owner review. Full owned container/VM teardown is the
clean boundary; don't kill broad PID patterns, delete unrelated archives,
prune all Podman images or run global Nix GC. Inspect owned processes/terminals,
stop only fixture resources, then follow parent harness teardown. No teardown,
physical-host restart, permission change or final production deployment has
been performed by this consolidation.
