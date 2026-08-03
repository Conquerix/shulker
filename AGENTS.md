# Codex repository context

This is Conquerix's personal flake-based Nix configuration. It manages NixOS
and nix-darwin hosts, Home Manager configuration, reusable profiles and
services, and 1Password-backed secrets.

## Repository map

- `system/hosts/` contains host entry points and hardware configuration.
- `system/profiles/` groups reusable machine roles.
- `system/modules/` contains reusable services and platform configuration.
- `system/users/` connects system users to Home Manager.
- `home/` contains shared Home Manager modules and defaults.
- `lib/`, `overlays/`, and `nix/` contain flake helpers and package changes.
- `lib/server-docs.nix` generates server reports from evaluated NixOS state.
- `.github/` contains validation, maintenance, and Wiki automation.

Host directories are discovered automatically by `flake.nix`. A NixOS host
that enables `shulker.system.profiles.server` automatically receives a
`server-docs-<host>` package and appears in the combined `server-docs` output.

## Working rules

- Inspect the relevant host, profile, and module before changing behavior.
- Preserve unrelated working-tree and staged changes; commit only task-scoped
  files and hunks.
- Keep `users.mutableUsers = false`. Preserve declarative password hashes and
  independent SSH recovery keys unless Conquerix explicitly changes that
  recovery policy.
- Never commit or print secret values, secret references, generated secret
  paths, password hashes, or service credentials in documentation.
- Do not edit generated server Markdown. Change the Nix configuration or
  `lib/server-docs.nix`, then rebuild the report.
- Treat deployment, reboot, destructive storage/database work, credential
  changes, and history rewrites as live-impacting operations that require
  explicit authorization.
- Before restarting a gaming host or session, check for active games with
  `pgrep -f 'steamapps/[c]ommon'` and do not interrupt them.

## Validation

Use the smallest relevant check while iterating, then validate in proportion
to the change:

```sh
# Evaluate every exported configuration and check.
nix flake check --no-build --all-systems

# Run the full flake checks when the change can affect builds or hooks.
nix flake check

# Build all generated server reports or one host report.
nix build .#server-docs
nix build .#server-docs-<host>

# Format Nix sources.
nix fmt
```

Track newly created Nix files before flake evaluation because Git flakes omit
untracked files. Pre-commit hooks and `nixfmt` may modify files; review, stage,
and retry the commit when that happens.

## Git conventions

- The default branch is `dev`.
- Prefer focused commits with imperative Conventional Commit-style subjects.
- Do not amend published commits, force-push, or rewrite shared history without
  explicit approval.
- When Codex materially contributes to a commit, append this trailer after a
  blank line so GitHub records the contribution:

  ```text
  Co-authored-by: openai-codex[bot] <215057067+openai-codex[bot]@users.noreply.github.com>
  ```

## Generated documentation and automation

- `nix build .#server-docs` creates the complete server report set.
- `scripts/sync-server-wiki.sh` updates only marker-managed Wiki pages and
  preserves unrelated manual pages such as `Home.md`.
- GitHub Actions validates changes, uploads generated reports, publishes the
  Wiki, opens weekly flake-input update pull requests, and receives grouped
  action updates from Dependabot.
- Keep actions pinned to full commit hashes and retain the release tag in a
  comment.
