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
