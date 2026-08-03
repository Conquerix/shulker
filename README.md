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

## Server documentation

Build all server reports into `result/`:

```sh
nix build .#server-docs
```

Each server also has a dedicated `server-docs-<host>` target. Reports include
enabled roles and services, network exposure, containers, storage, persistence,
backup coverage, secret names, operational warnings, and deployment commands.
Secret values and references are excluded.

Do not edit generated Markdown. Change the host or module configuration, or
extend `lib/server-docs.nix`, then rebuild the relevant target. A NixOS host that
enables `shulker.system.profiles.server` automatically receives a documentation
target and appears in the combined output.

## Development and validation

Use the smallest relevant check while iterating, then validate in proportion to
the change:

```sh
# Evaluate every exported configuration and check.
nix flake check --no-build --all-systems

# Run the full flake checks, including build-backed checks.
nix flake check

# Build all server reports or one host report.
nix build .#server-docs
nix build .#server-docs-<host>

# Format the Nix sources.
nix fmt

# Enter the development shell with repository checks installed.
nix develop

# Apply a NixOS host configuration.
sudo nixos-rebuild switch --flake .#<host>

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
server reports to the [repository Wiki](https://github.com/Conquerix/shulker/wiki).
Dependabot groups updates to pinned GitHub Actions into weekly pull requests.

See the [automation guide](.github/README.md) for workflow triggers,
permissions, and Wiki synchronization behavior.

## Origins

Originally forked from EmergentMind's
[nix-config](https://github.com/EmergentMind/nix-config) and since adapted to
this host and module layout.
