# Hermes Agent

Shulker declares `shulker.system.modules.hermes-agent.instances`, an attribute set
of independent agents. Explicit imports load options, shared instance generation
and host administration; there is no special root agent or nested Engineer path.
Each enabled instance gets the same OCI, systemd, OpNix, tmpfiles, persistence and
backup implementation. The host selects capabilities and initial data.

| Instance | Container / unit | State | Dashboard |
| --- | --- | --- | --- |
| Overseer | `hermes` / `docker-hermes` | `/var/lib/hermes-overseer` | loopback 23234, https://hermes.shulker.link |
| Engineer | `hermes-engineer` / `docker-hermes-engineer` | `/var/lib/hermes-engineer` | disabled, no published ports |

The image remains pinned to the tested stable digest; this refactor is not an
upgrade. Both run at UID/GID 10000 with 4 GiB RAM, two CPUs and 512 PIDs. Each
mounts only its own `data` at `/opt/data`, `workspace` at `/workspace`, and its
validated managed environment. Engineer has no SSH key, host workspace, Docker
socket, dashboard or vault account. This is a container mount boundary, not
separate host Unix identities. Both join the OmniRoute bridge, so it is not
network isolation from other bridge peers. The dashboard remains private behind
Pangolin SSO; the API binds loopback inside its container.

## Ownership and initial data

NixOS owns image/version, lifecycle, network, managed secrets and access policy,
capabilities, persistence and backups. Hermes owns its writable configuration,
identity, memory, sessions, plugins, skills and other learned state. Learning
cannot expand deployment or host authority.

`initial.files` maps non-secret source paths to relative `data/` or `workspace/`
paths. Files are created exclusively only if absent; existing files and symlinks
are not replaced. Overseer's existing identity/memory/workspace seed files remain
initial context, not reconciled templates. Initial file writes run as the
unprivileged Hermes user so writable symlinks cannot redirect root operations.
Do not place credentials in Nix source data or use this to write `config.yaml`.

`initial.settings` maps dotted config keys to string arguments for native
`hermes config set`; `initial.plugins` names native `hermes plugins enable`
commands. They run only if `data/config.yaml` is absent, in a transient container
using the exact pinned image, UID/GID 10000, no network and no credentials. Native
commands construct a private staging config; only a fully successful config is
published, without replacing an existing file. A failure blocks startup and can
be retried. Existing config (including an upstream starter config) is never
modified. Existing Engineer identity, model, Discord activation, memory and
sessions therefore survive. Fresh Engineer state receives the declared model
and Discord plugin defaults; add approved initial identity files to specialize
fresh identities. Existing identities always remain native mutable state.

Initial settings are not ongoing desired state. To change a running agent, use
native commands, not hand-edits of its YAML:

```sh
sudo docker exec hermes hermes config get model.default
sudo docker exec hermes hermes config set model.default cx/gpt-6.1-sol
sudo docker exec hermes-engineer hermes plugins show discord-platform
```

The model defaults use native OmniRoute at `http://omniroute:20128/v1`, default
`cx/gpt-6.1-sol`, and an environment-variable credential reference rather than a
literal key. Subscription authentication stays in OmniRoute; no paid API fallback
is introduced. Existing runtime settings are not reset by this declaration.

## Credentials and managed access policy

All agents use **OpNix source files**, including Overseer. There is no startup
`op read`, bootstrap-token fetch chain or network vault dependency in the
renderer. Every `credentials.<label>` declares an exact `requiredKeys` set and a
case-sensitive reference. OpNix provisions separate instance-scoped secret names
and service dependencies. Credential reference strings stay in Nix, never in
evaluated public documentation.

Preserve source labels exactly: Overseer's **[AI] Overseer** item in **Shulker**
uses **Hermes / Dashboard environment**, **Hermes / Provider environment** and
**Hermes / Discord environment**. Engineer's **[AI] Engineer** item uses
**Hermes / Discord Environment** (capital E), addressed by its existing stable
item/section/field IDs. Engineer's provider source remains the existing host
**Hermes / Provider environment** field. Do not replace that inference-only
credential with Overseer's administrative or dashboard credentials.

Sources contain unquoted, single-line `KEY=value` entries. Literal `$`, `#` and
`=` are supported without expansion. Missing, empty, duplicate, extra or malformed
keys, quotes, surrounding whitespace and inline-comment syntax are rejected.
Each source must contain exactly its declared nonempty keys. Cross-source
duplicates, capability tokens and policy keys in credential sources are refused.
Dashboard sources require the three basic-auth variables and `API_SERVER_KEY`;
provider sources require `HERMES_OMNIROUTE_API_KEY`; Discord sources require only
`DISCORD_BOT_TOKEN`.

The shared renderer validates every source and optional SSH private key before
publishing a single private runtime generation. It atomically switches `current`
only on success, retains the prior complete generation for recovery, and fails
startup rather than silently using stale values. Files are mode 0400, owned by
Hermes; private runtime directories are mode 0700. `/run` clears at reboot and
is not persistent or backed up. The environment is mounted read-only at
`/etc/hermes/.env` and consumed by Docker from the same validated generation.
This Hermes managed-secret layer is needed for profile isolation; ambient Docker
environment alone is not enough. Never copy these keys into writable profile
`.env` files as a workaround.

Discord requires an explicit numeric user allowlist. Nix injects the allowlist,
allow-all false, mentions required and bot replies disabled into both the managed
environment and container policy. Direct messages do not require mentions.
Use dedicated bot accounts per instance. Enable Message Content and Server
Members intents and grant messaging/history/attachment/reaction/thread permissions.
Native `discord.free_response_channels` can select deliberate mention-free
channels. Enabling the plugin or observing a bot-origin message does not prove
user-origin authorization works.

**Refresh semantics changed:** editing a vault field alone, or restarting Hermes
alone, does not refetch it. Refresh host OpNix provisioning through the approved
checked deployment procedure, inspect its reverse dependencies, then verify the
agent. A changed secret configuration can restart Overseer, OmniRoute and other
dependents. Never promise an agent-only refresh or restart OpNix casually.

## Independent privileged capabilities

`serviceAccount.enable` and its explicit token reference grant the 1Password CLI
capability. Only enabled instances receive the private token mount, the official
CLI from locked nixpkgs and the `op` wrapper. The wrapper reads the token from its
private mount, not an environment source. Startup credential provisioning never
uses this account. Overseer retains its approved vault-wide authority; Engineer
does not inherit it. Use `op run` or a subprocess to consume credentials without
printing them. Writing a vault value does not rotate an application credential.

`hostAdministration.enable` independently grants a dedicated host SSH user,
verified host key, read-only private-key mount and host-gateway alias. Overseer
retains `hermes-operator`, its existing public keys and unrestricted passwordless
**ALL root sudo**, intentionally unchanged. No wheel/Docker/journal group is
added. sudo-rs permits the non-wheel account. Strict SSH host-key checking and
restricted authorized keys disable forwarding. Root authority can override host
protections and read host secrets; private mounts do not constrain it.

Use `ssh shulker 'sudo -n id -u'` (expected `0`) and inspect `sudo -l` only during
approved verification. Workspace instructions require approval before deployments,
upgrades, destructive operations, server credential changes, host permission
changes and other service changes. Check idle state before routine restarts;
announce self-restarts and verify recovery. No deployment is authorized by this
runbook.

## Validation and migration

Run offline regression tests and the evaluated structural contract:

```sh
python3 tests/hermes-credentials.py system/modules/nixos/services/hermes-agent/render-credentials.py
python3 tests/hermes-bootstrap.py system/modules/nixos/services/hermes-agent/bootstrap.py
nix build .#checks.x86_64-linux.hermes-credentials-contract
nix build .#checks.x86_64-linux.hermes-instances-contract
nix flake check --no-build --all-systems
nix build .#nixosConfigurations.shulker.config.system.build.toplevel
```

The structural check examines generated Overseer/Engineer services and a third
unprivileged instance rendered by the same function, including mounts, ports,
OpNix scopes, ordering, persistence and backups. Python tests use synthetic
fixtures, not live credentials. Native bootstrap tests simulate the CLI contract;
the exact pinned image must still be tested before approving fresh provisioning.

Migration is a reviewed NixOS deployment, never a replacement `docker run`:

1. In an approved idle window record image IDs, mounts, messaging identities and
   unit state privately. Confirm the pinned manifest resolves to the same image
   ID (known pre-migration ID
   `sha256:373ddd5e6649f525b17993e1c885cdf1352127f8e98fd329140a73237125e52f`).
   A local image ID is not a registry manifest digest. Do not upgrade during cutover.
2. Stop gateways before any private consistent snapshot/copy of their state,
   including SQLite databases. Verify UID/GID 10000. Inspect `findmnt -T` for each
   state tree and the `/nix/persist` backing directory: an empty impermanence
   backing directory must not hide existing tmpfs state. If migration is needed,
   preserve metadata while copying the stopped tree, verify it, and keep it
   stopped so state cannot diverge. Never reinitialize or delete live state.
3. Review `sudo shulker-rebuild dry-activate --flake .#shulker`, OpNix references
   and reverse dependencies. Renamed instance-scoped secrets and added Overseer
   sources change provisioning and can affect other dependents. Verify the host
   provisioning account can resolve every new reference without exposing values.
   Strict extra-key rejection may reveal previously tolerated source contents;
   inspect names privately and resolve deliberately, never weaken scopes.
4. If a legacy imperative Engineer container still exists, disable autostart,
   stop it, verify no writer remains, then remove only its container object at
   cutover without deleting bind-mounted state. Never run two gateways against
   the same bot/state. Use checked `test`, verify, then checked `switch` only with
   approval. On failure stop the new unit and use reviewed NixOS rollback/recovery;
   a rollback generation without Engineer does not manage it.

After an approved activation, verify exact targets without exposing secrets:

```sh
sudo systemctl is-active docker-hermes docker-hermes-engineer docker-omniroute
sudo docker inspect hermes-engineer --format '{{.Image}} {{json .Mounts}} {{json .HostConfig.PortBindings}}'
sudo stat -c '%a %u:%g %n' /run/hermes-engineer-managed/current/.env
sudo docker exec hermes-engineer hermes gateway status
sudo docker exec hermes-engineer hermes config get model.default
sudo docker exec hermes-engineer hermes chat -Q --max-turns 3 --run-budget 90 \
  -q 'Identify yourself, then run python --version with your terminal tool and report the result.'
```

Confirm container names, image IDs, exact mounts/ports and managed key names;
Engineer must still have no privileged mounts or published ports. Check saved
identity, model, sessions, plugins, memories and workspace survive. For each bot,
have the allowed user send a real DM and server mention; verify replies and
negative authorization cases (other users, bots, unsolicited channel messages).
Native memory and longer `workspace/knowledge` reports remain writable; Overseer's
knowledge remains published privately through Quartz. A fresh Discord `/new`
loads current context; a gateway restart alone does not reset session snapshots.

Each complete state tree is included in Borgmatic and, when enabled, impermanence.
State backups are private and can include credentials/conversations. Verify
backup sources/backing directories, inspect the next archive and restore into an
empty directory, never over live data. File backup during SQLite writes is not
proof of consistent restore: use quiesced snapshots for migration recovery.
Retain previous recovery items and retired state until rollout acceptance.
