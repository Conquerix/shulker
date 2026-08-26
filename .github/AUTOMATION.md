# Repository automation guide

The workflows in this directory keep the configuration validated, dependencies
current, and the repository Wiki synchronized.

## Checks

[`workflows/check.yml`](workflows/check.yml) runs on pushes and pull requests. It
evaluates all flake outputs, builds the repository hook derivation, builds the
Wiki publication contract suite, builds the generated host reports and
infrastructure topology, and retains those outputs as a 14-day workflow
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

## Seafile stack release reviews

[`workflows/check-seafile-release.yml`](workflows/check-seafile-release.yml)
runs every Monday and on demand. It reads the evaluated Warden release matrix
once, then checks the official Docker Hub tag API independently for stable
Seafile, MariaDB 10.11, Redis 7.4, SeaSearch 1.0, Notification 13.0, Metadata
13.0, and OnlyOffice 9.4 releases.

When a component is newer within its reviewed release line, the workflow
creates or refreshes one open issue carrying the
`<!-- seafile-release-monitor -->` ownership marker and the title
`chore: review Seafile stack updates`. It checks the marker before editing, so
a similarly titled human-authored issue is never changed. The issue records
every configured and detected version, links to upstream release information,
and provides compatibility, migration, security, backup, restore-rehearsal,
digest-refresh, validation, deployment-approval, and post-deployment review
items.

The workflow never edits image pins. It has only `contents: read` and
`issues: write`, and never commits or pushes repository changes, opens a pull
request, deploys, or mutates a host. The regular checks and flake-update validation explicitly build
the build-backed `seafile-contract-suite`; all live changes remain separate,
reviewed operator actions.

## Repository Wiki

[`workflows/wiki.yml`](workflows/wiki.yml) republishes the documentation after
relevant configuration or `docs/wiki/**` changes reach the default branch,
every Monday as a self-healing run, and on demand.

The repository Wiki is publication output, not an authoring surface.

Authored runbooks come from `docs/wiki/` and are copied to these flat Wiki
filenames:

- `Service-Hermes-WebUI.md`;
- `Service-GrapheneOS-WebDAV.md`;
- `Service-Seafile.md`;
- `Service-Immich.md`;
- `Service-Paperless.md`;
- `Operations-Backup-and-Restore.md`;
- `Operations-Security-and-Recovery.md`;
- `Project-Development.md`.

Evaluated pages are built from Nix configuration and include:

- `Servers.md`, the generated index;
- `Home.md`, `Fleet.md`, and `Services.md`, the fleet overview and service
  catalog;
- `Public-Services.md` and `Infrastructure.md`, the sanitized Pangolin inventory
  and split Mermaid topology;
- `Operations.md` and `Automation.md`, the fleet runbook and maintenance
  pipeline;
- `_Sidebar.md` and `_Footer.md`, persistent Wiki navigation and provenance.

Host pages come from evaluated host reports: `Host-<host>.md` provides one
report for every NixOS and nix-darwin host.

`wiki-pages.txt` is the non-host page inventory. The three-input synchronizer
uses that inventory together with the host-report directory to publish the
complete owned page set.

The synchronization script refuses to overwrite a page without its generated
marker. The original minimal Shulker `Home.md` is recognized as a one-time
migration source. Unrelated manual Wiki pages are preserved, and stale generated
pages are removed.

The workflow uses its short-lived, repository-scoped `GITHUB_TOKEN` with
`contents: write`; no long-lived Wiki credential is stored. Enable the repository
Wiki, then run **Publish repository Wiki** manually once and confirm the generated
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

`topology/public.json` is the sanitized boundary for external control-plane
data. Refresh it manually from the repository root with:

```sh
PANGOLIN_API_ENDPOINT=https://api.example.com \
PANGOLIN_ORG_ID=example \
PANGOLIN_API_KEY=... \
scripts/fetch-pangolin-topology.sh
```

The collector deliberately excludes internal target addresses, ports, private
resources, access policies, identities, and credentials. Detailed external
snapshots must remain in ignored `topology/private*.json` files and must never
be published to the repository or Wiki.

On a self-hosted Pangolin control plane, enable and expose the Integration API
with the root-only, reversible bootstrap helper:

```sh
sudo nix shell nixpkgs#yq-go --command \
  scripts/configure-pangolin-integration-api.sh api.example.com
```

It preserves the existing YAML, creates root-only backups, validates the edited
files, and rolls back if the Pangolin API does not become healthy. The helper
briefly restarts Pangolin and Traefik, so schedule this operation like any other
short control-plane interruption.

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
