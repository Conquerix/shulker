# Development and validation

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

## Repository automation

GitHub Actions validate every push and pull request, retain generated reports
as workflow artifacts, propose weekly flake-input updates, and publish the
host reports to the [repository Wiki](https://github.com/Conquerix/shulker/wiki).
Dependabot groups updates to pinned GitHub Actions into weekly pull requests.

| Routine | Cadence | Result |
| --- | --- | --- |
| Checks | Push and pull request | Validates the flake and builds generated reports |
| Publish infrastructure Wiki | Relevant push, weekly, or manual | Republishes evaluated reports and sanitized topology |
| Update flake inputs | Weekly or manual | Opens or refreshes a validated dependency pull request |
| Check Paperless-ngx release | Weekly or manual | Opens or refreshes one marked review issue when upstream is newer |
| Check Seafile stack releases | Weekly or manual | Opens or refreshes one marked review issue when a reviewed component is newer |

The Paperless monitor is deliberately non-deploying: it cannot write repository
contents and never edits pins, commits code, or touches Warden. Its issue asks
the reviewer to treat the Paperless-ngx, PostgreSQL, Valkey, Gotenberg, and Tika
tags and immutable digests as one compatibility set, then perform the documented
export, backup, validation, and checked deployment sequence.

The Seafile stack monitor is likewise non-deploying. It compares the evaluated
Seafile, MariaDB, Redis, SeaSearch, Notification, Metadata, and OnlyOffice
release matrix with their reviewed upstream release lines, then maintains one
marker-owned compatibility-review issue. It never edits pins, commits, pushes,
opens a pull request, deploys, or mutates a host.

See the [automation guide](https://github.com/Conquerix/shulker/blob/dev/.github/README.md) for workflow triggers,
permissions, and Wiki synchronization behavior.


## Related documentation

- [Automation](https://github.com/Conquerix/shulker/wiki/Automation)
- [Operations](https://github.com/Conquerix/shulker/wiki/Operations)
- [Services](https://github.com/Conquerix/shulker/wiki/Services)
