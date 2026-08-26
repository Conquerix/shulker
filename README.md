# Shulker

## What this repository is

Shulker is the infrastructure-as-code source of truth for Conquerix's personal
fleet: eight NixOS machines and one macOS machine managed with nix-darwin. A
single Nix flake declares their operating systems, hardware-specific settings,
packages, user environments, desktop and gaming roles, and self-hosted services.

The repository also contains reusable modules and profiles, Home Manager
configuration, 1Password-backed secret wiring, deployment validation,
automation, and backup and recovery runbooks. Its purpose is to make the fleet
reproducible and its services operable from one reviewed configuration. It is
personal infrastructure rather than an application or reusable Nix
distribution, so treat it as a reference rather than a drop-in configuration.

## Layout and hosts

- `system/hosts/` contains machine-specific NixOS and Darwin entry points.
- `system/profiles/` groups reusable desktop, server, Steam Machine, and
  MacBook behavior.
- `system/modules/` contains reusable services and platform configuration.
- `system/users/` connects system users to Home Manager configuration.
- `home/` contains shared Home Manager modules and defaults.
- `lib/`, `overlays/`, and `nix/` contain flake helpers, package overrides, and
  compatibility configuration.
- `.github/` contains validation, dependency-maintenance, and Wiki automation.

The flake discovers host directories automatically. Each host imports its
hardware configuration and enables only the profiles and modules it needs.

NixOS hosts: `enderdragon`, `endermite`, `guardian`, `phantom`, `shulker`,
`silverfish`, `warden`, and `wither`. Darwin host: `herobrine`.

## Documentation

The [repository Wiki](https://github.com/Conquerix/shulker/wiki) is the
navigable operator-facing publication, with its table of contents on the Home
page. Fleet and project runbooks are authored under
[version-controlled sources](docs/wiki/); each migrated service owns its
canonical runbook beside its module under `system/modules/nixos/services/`.
Changes remain reviewable with the configuration.

The [server documentation guide](system/hosts/nixos/README.md) explains the
evaluated per-host reports. The [automation guide](.github/AUTOMATION.md) documents
workflow permissions and synchronization behavior. Do not edit generated
Markdown; change its authored source, host/module configuration, or generator.

Build the evaluated documentation outputs with:

```sh
nix build .#host-docs
nix build .#host-docs-<host>
nix build .#infrastructure-data
nix build .#infrastructure-diagram
nix build .#wiki-docs
```

`wiki-docs` assembles the authored runbooks with evaluated fleet, service,
topology, public-service, operations, and automation pages. `host-docs` builds
the NixOS and nix-darwin reports that the publication workflow adds separately.
Secret values, references, generated paths, password hashes, and credentials
must never enter generated documentation.

## Validation and deployment

Use the smallest relevant check while iterating, then validate in proportion
to the change. The evaluation baseline is:

```sh
nix flake check --no-build --all-systems
```

Run `nix flake check` when build-backed checks are relevant. Track new Nix files
before evaluation because Git flakes omit untracked files. `nix fmt` and
pre-commit hooks may modify files; review and stage those edits before retrying
a commit.

For a checked NixOS deployment, validate first and advance through each step:

```sh
nix flake check --no-build --all-systems
nix build .#nixosConfigurations.<host>.config.system.build.toplevel
sudo shulker-rebuild dry-activate --flake .#<host>
sudo shulker-rebuild test --flake .#<host>
sudo shulker-rebuild switch --flake .#<host>
```

On the first deployment of the wrapper, use
`sudo nix run .#checked-rebuild -- switch --flake .#<host>`. Apply Darwin with
`darwin-rebuild switch --flake .#herobrine`. Deployment is a live-impacting
operation and always requires explicit approval.

## Maintenance conventions

- The default branch is `dev`.
- Inspect the relevant host, profile, module, evaluated configuration, and
  runtime state before changing behavior.
- Preserve unrelated working-tree and staged changes; keep commits focused and
  use imperative Conventional Commit-style subjects.
- Keep agent plans and specifications under uncommitted `.agent-work/`.
- Do not amend published commits, force-push, or rewrite shared history without
  explicit approval.
- Keep GitHub Actions pinned to full commit hashes with release tags in comments.

## Security, recovery, and operational safety

NixOS hosts expect an opnix service-account token at `/etc/opnix-token`.
`shulker-rebuild` evaluates the prospective host and resolves every configured
secret before rebuilding. Values stay in a private temporary directory that is
removed before the rebuild; failures report logical names only. Rollbacks do
not need this check. `--skip-secret-check` is an explicit emergency escape hatch
when provisioned secrets are known good, not a routine deployment option.

Keep `users.mutableUsers = false`, declarative password hashes, and independent
SSH recovery keys unless deliberately changing the recovery model. Passwords
provide console and sudo recovery while SSH password authentication remains
disabled. Generate a replacement yescrypt hash with:

```sh
nix shell nixpkgs#mkpasswd --command mkpasswd -m yescrypt
```

Deployments, reboots, credential changes, destructive storage/database work,
and Git history rewrites require explicit approval. Before restarting a gaming
host or session, check for an active game and do not interrupt it:

```sh
pgrep -f 'steamapps/[c]ommon'
```

Borgmatic performs weekly repository checks and monthly archive checks. After
backup changes, verify the repository and inspect archives:

```sh
sudo borgmatic check --force
sudo borgmatic repo-list
```

Test file restoration into an empty temporary directory, never over live data.
Database restoration is separate destructive work and requires validation of
the extracted backup and target service. See the authoritative
[backup and restore](docs/wiki/operations/backup-and-restore.md) and
[security and recovery](docs/wiki/operations/security-and-recovery.md) guides.

## Automation

GitHub Actions validate pushes and pull requests, retain generated reports,
propose weekly flake-input updates, run non-deploying Paperless and Seafile
release monitors, and publish the assembled documentation. Dependabot groups
pinned-action updates into weekly pull requests. See
[Automation](https://github.com/Conquerix/shulker/wiki/Automation) for triggers,
permissions, publication boundaries, and maintenance behavior.

## Origin

Originally forked from EmergentMind's
[nix-config](https://github.com/EmergentMind/nix-config) and since adapted to
this host and module layout.
