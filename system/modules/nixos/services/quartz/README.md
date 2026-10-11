# Quartz

One private reading site presents published knowledge from all configured agents.
The overview links to a separate section for each agent, starting with Overseer.
Pangolin protects https://notes.shulker.link with the owner's PocketID identity;
the backend is bound only to 127.0.0.1:23251. Search, navigation, backlinks and
the graph cover the published sections.

## Content and agents

`agents.<id>.contentDir` selects each agent's knowledge folder. The builder mounts
these folders read-only under `/notes/<id>` and creates a snapshot for rendering.
It never modifies the source. IDs are stable lowercase URL names; display names
can differ. To add an agent, declare its display name and approved publishing
directory in the host's Quartz configuration. Sources must be readable by the
Hermes container UID, 10000; other private agent state remains separate.

Overseer publishes `/var/lib/hermes-clean/workspace/knowledge` under `/overseer/`.
Only selected knowledge directories are mounted, not configuration, credentials,
sessions, skills or compact native memory. The native memory view remains in each
agent's dashboard. Hidden files, drafts, private folders and symlinks are excluded.
The entire site currently uses the owner's access policy: an agent section is
organization, not a separate authentication boundary.

Markdown and attachments remain the source of truth. Each agent may supply its
own `index.md`; otherwise the publisher provides a simple section landing page.
Links resolve relative to their note so matching filenames in different agent
sections stay distinct. Use explicit relative paths for links between folders.
No repository push, Obsidian Sync account or external hosting service is involved.

## Rendering and serving

NixOS manages two Docker containers without Compose. `quartz-build` uses upstream
Quartz 4.5.2 at commit `4923affa7722dfc751f1074348e6dad214fe0c08`, built with its
unchanged Dockerfile and pinned by image ID. `quartz-web` uses the pinned official
Nginx image. Both run as UID/GID 10000 with no extra Linux capabilities, a
read-only root filesystem and bounded writable temporary storage. The builder
has no network access, host credentials or Docker socket. Analytics, remote
fonts, RSS and sitemap generation are disabled.

Every minute, the builder checks notes and configuration for changes. It builds
changed content in a private temporary directory, then atomically switches the
site symlink after success. Failure retains the previous working site and retries
on the next interval. The web container sees only the generated site volume,
read-only. It uses private/no-store cache headers and disables search indexing.

```sh
sudo systemctl status docker-quartz-build docker-quartz-web
sudo docker logs --tail 50 quartz-build
sudo docker logs --tail 50 quartz-web
```

Renderer errors may mention private note names or text; inspect them privately.

## Versions and recovery

The pinned local builder image is recoverable from the root-only compressed
archive and checksum under `/var/lib/quartz/images`. This directory is persistent
and backed up. Source notes are already backed up by their agent; generated HTML
is disposable and excluded from backups.

To update, check out a fixed upstream revision, build its Dockerfile, validate
the Quartz configuration against that version, and test sample content offline
before changing the Nix image pin. Save and checksum the new image archive before
deployment. The builder's fingerprint includes the image ID so an image change
rebuilds the site. After losing generated state, the first build recreates it.
After losing the Docker image, verify its archive checksum and use `docker load`.

Acceptance covers two agents, note updates and deletions, a failed build retaining
the previous site, source write rejection, hidden-file exclusion, extensionless
URLs, anonymous access denial and owner browser access. Test publication with
sample notes before pointing a candidate at the real agent folders.
