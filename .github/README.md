# Repository automation

The workflows in this directory keep the configuration validated, dependencies
current, and the server Wiki synchronized.

## Checks

[`workflows/check.yml`](workflows/check.yml) runs on pushes and pull requests. It
evaluates all flake outputs, builds the repository hook derivation, builds the
generated server reports, and retains those reports as a 14-day workflow
artifact.

## Flake input updates

[`workflows/update-flake.yml`](workflows/update-flake.yml) runs every Monday and
on demand. It updates `flake.lock`, validates the result, and creates or refreshes
the `automation/update-flake-inputs` pull request. It never pushes dependency
updates directly to the default branch.

The workflow needs `contents: write` and `pull-requests: write`. Repository
settings must permit GitHub Actions to create pull requests. Pull requests made
with `GITHUB_TOKEN` may not trigger another workflow run, so the update workflow
runs the complete validation before publishing its branch.

## Server Wiki

[`workflows/wiki.yml`](workflows/wiki.yml) rebuilds the server reports after
relevant changes reach the default branch, every Monday as a self-healing run,
and on demand. It publishes these generated Wiki pages:

- `Servers.md`, the generated index;
- `Server-<host>.md`, one evaluated report per server-profile host.

The synchronization script refuses to overwrite a page without its generated
marker. Unrelated manual Wiki pages are preserved, and stale generated host pages
are removed.

The workflow uses its short-lived, repository-scoped `GITHUB_TOKEN` with
`contents: write`; no long-lived Wiki credential is stored. Enable the repository
Wiki, then run **Publish server Wiki** manually once and confirm the generated
`Servers` page.

## Action updates

[`dependabot.yml`](dependabot.yml) groups GitHub Action updates into a weekly
pull request. Workflow actions are pinned to full commit hashes, with the release
tag recorded in a comment for auditability.
