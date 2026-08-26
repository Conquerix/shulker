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
assembled [repository Wiki](https://github.com/Conquerix/shulker/wiki).
Dependabot groups updates to pinned GitHub Actions into weekly pull requests.

The publication assembles authored runbooks from fleet and project documents in
`docs/wiki/` plus colocated direct service `README.md` files. It combines
evaluated non-host pages from Nix with host pages from evaluated `host-docs` reports.

| Routine | Cadence | Result |
| --- | --- | --- |
| Checks | Push and pull request | Validates the flake and builds generated reports |
| Publish repository Wiki | Relevant default-branch push, weekly, or manual | Validates and republishes authored, evaluated, and host pages |
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

See the [automation guide](https://github.com/Conquerix/shulker/blob/dev/.github/AUTOMATION.md) for workflow triggers,
permissions, and Wiki synchronization behavior.

## Adding a service

Add every retained deployable service under
`system/modules/nixos/services/<service>/`. Create its `default.nix` NixOS
entry point, canonical `README.md` runbook, and sorted entry in
`system/modules/nixos/services/default.nix` in the same reviewed change. Split
implementations use an explicit, sorted `imports` list; helpers, tests, and
package expressions are never imported implicitly.

The README first line is exactly `# <Title>`; the title uses ASCII letters and
digits separated by single spaces, normalizes to the directory name, and
publishes as `Service-<Title>.md`. Keep only one H1 outside fenced code blocks
and use canonical absolute links. Canonical service READMEs are the only source
of service Wiki pages: never create a legacy map, copy a runbook, or add a
naming override. Keep secret values and private identifiers out of
documentation.

Stage new Nix files before evaluation. Validate the README title and links,
the exact service-directory/import manifest, generated Wiki navigation and
page equality, and the affected host options, units, inventories, persistence,
backup, secret names, and routes before committing.

[Pangolin topology operations](https://github.com/Conquerix/shulker/blob/dev/.github/AUTOMATION.md#pangolin-topology-enrichment)
documents the sanitized boundary, manual collector, Integration API bootstrap,
and restart and rollback behavior.


## Related documentation

- [Automation](https://github.com/Conquerix/shulker/wiki/Automation)
- [Operations](https://github.com/Conquerix/shulker/wiki/Operations)
- [Services](https://github.com/Conquerix/shulker/wiki/Services)
