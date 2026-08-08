# Repository automation

The workflows in this directory keep the configuration validated, dependencies
current, and the server Wiki synchronized.

## Checks

[`workflows/check.yml`](workflows/check.yml) runs on pushes and pull requests. It
evaluates all flake outputs, builds the repository hook derivation, builds the
generated host reports and infrastructure topology, and retains those outputs
as a 14-day workflow artifact.

## Flake input updates

[`workflows/update-flake.yml`](workflows/update-flake.yml) runs every Monday and
on demand. It updates `flake.lock`, validates the result, and creates or refreshes
the `automation/update-flake-inputs` pull request. It never pushes dependency
updates directly to the default branch.

The workflow needs `contents: write` and `pull-requests: write`. Repository
settings must permit GitHub Actions to create pull requests. Pull requests made
with `GITHUB_TOKEN` may not trigger another workflow run, so the update workflow
runs the complete validation before publishing its branch.

## Paperless release reviews

[`workflows/check-paperless-release.yml`](workflows/check-paperless-release.yml)
runs every Monday and on demand. It compares the evaluated Warden Paperless
version with the latest upstream GitHub release. When upstream is newer, it
creates or refreshes one open issue carrying the
`<!-- paperless-release-monitor -->` marker. A similarly titled human-authored
issue is never edited.

The workflow has only `contents: read` and `issues: write`. It reports the
configured and latest versions and supplies the export, backup, compatibility,
validation, and deployment review checklist. It never changes the repository
or a host. Review all five pinned images—Paperless-ngx, PostgreSQL, Valkey,
Gotenberg, and Tika—as one compatibility set before upgrading.

## Server Wiki

[`workflows/wiki.yml`](workflows/wiki.yml) rebuilds the host reports after
relevant changes reach the default branch, every Monday as a self-healing run,
and on demand. It publishes these generated Wiki pages:

- `Servers.md`, the generated index;
- `Host-<host>.md`, one evaluated report for every NixOS and nix-darwin host;
- `Home.md`, `Fleet.md`, and `Services.md`, the fleet overview and service
  catalog;
- `Public-Services.md` and `Infrastructure.md`, the sanitized Pangolin inventory
  and split Mermaid topology;
- `Operations.md` and `Automation.md`, the fleet runbook and maintenance
  pipeline;
- `_Sidebar.md` and `_Footer.md`, persistent Wiki navigation and provenance.

The synchronization script refuses to overwrite a page without its generated
marker. The original minimal Shulker `Home.md` is recognized as a one-time
migration source. Unrelated manual Wiki pages are preserved, and stale generated
pages are removed.

The workflow uses its short-lived, repository-scoped `GITHUB_TOKEN` with
`contents: write`; no long-lived Wiki credential is stored. Enable the repository
Wiki, then run **Publish infrastructure Wiki** manually once and confirm the generated
`Home` and `Fleet` pages.

### Pangolin topology enrichment

The Wiki workflow uses the committed empty/sanitized snapshot when Pangolin API
access is not configured. To refresh it from the live control plane, configure:

- repository variable `PANGOLIN_API_ENDPOINT`, containing the API origin without
  `/v1`;
- repository variable `PANGOLIN_ORG_ID`;
- repository secret `PANGOLIN_TOPOLOGY_API_KEY`, containing a read-only
  organization API key limited to listing sites, public resources, targets, and
  domains.

For Pangolin's permission selector, the exact required actions are `listSites`,
`listResources`, `listTargets`, and `listOrgDomains`. No create, update, delete,
identity, policy, role, or log permission is needed. Create the key under
**Organization → API Keys** and copy it directly into the GitHub secret prompt;
the key is shown only once:

```sh
gh secret set PANGOLIN_TOPOLOGY_API_KEY --repo Conquerix/shulker
```

The collector holds raw API responses in a private temporary directory, writes
only the sanitized public schema, and removes the temporary responses on exit.
The API key is unrelated to Wiki authentication and must never be committed.

## Action updates

[`dependabot.yml`](dependabot.yml) groups GitHub Action updates into a weekly
pull request. Workflow actions are pinned to full commit hashes, with the release
tag recorded in a comment for auditability.
