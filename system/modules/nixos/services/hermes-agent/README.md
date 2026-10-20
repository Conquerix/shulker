# Hermes Agent

Shulker runs the official Hermes image as Overseer (with its built-in dashboard)
and an optional isolated Engineer Discord gateway. NixOS controls the image
versions and the `docker-hermes` / `docker-hermes-engineer` services. Set `image`
to a tested tag/digest to upgrade; configuration remains editable inside Hermes.

Data is under /var/lib/hermes-clean/data, and the mounted workspace is under
/var/lib/hermes-clean/workspace. The dashboard listens on loopback port 23234
and is published privately through Pangolin at https://hermes.shulker.link.
Set `credentialItem` to this agent's 1Password item reference. Shulker uses the
existing **[AI] Overseer** item in the **Shulker** vault. Its **Hermes** section
holds the concealed **Dashboard environment**, **Provider environment** and
**Discord environment** fields. Store unquoted, single-line `KEY=value` entries;
quoted values, surrounding whitespace and inline-comment syntax are refused
because Docker and Hermes would parse them differently. Literal `$`, `#` and
`=` are supported without expansion. The provider field carries Overseer's own
OmniRoute inference key; model configuration references its environment variable.

OpNix bootstraps only the dedicated service-account token from the item's
**1Password / Service account token** field. On every Hermes start, the startup
renderer uses that account to fetch the configured fields directly from the
vault. It publishes a complete private runtime generation only after every
required value and the SSH key validate. A failed refresh stops startup and
retains the last complete generation, including after terminal startup failures
or an explicit stop. The runtime directory is cleared on reboot. A failed
refresh does not silently use stale values.
The loader's CLI configuration stays inside the private runtime directory;
it does not depend on systemd providing `HOME`.

The generated environment is also mounted read-only as `/etc/hermes/.env`.
Hermes' managed-secret layer keeps these credentials available inside isolated profile scopes; Docker
environment variables alone are not sufficient when gateway multiplexing is
enabled. The runtime file is readable by the Hermes user, regenerated from
1Password on each service start, and excluded from persistent state and backups.
Never copy these keys into the writable profile's `.env` to work around a missing
credential. Future agents with different credentials need separate managed state.
The same managed layer carries the NixOS Discord allowlist, mention requirement
and bot-reply policy so profile isolation preserves those access restrictions.

When OmniRoute is enabled on the host, both containers join the `omniroute`
Docker bridge. Hermes uses `http://omniroute:20128/v1` directly; the dashboard
remains private through Pangolin. The network permits outbound provider traffic.
Hermes' native `omniroute` provider uses Chat Completions, with
`cx/gpt-6.1-sol` as default and `cx/gpt-6-astra` also available. Its key is
restricted to those two models and cannot manage OmniRoute. Subscription
authentication stays in OmniRoute, with no paid API fallback.

Model settings remain in the writable data directory. Change them through
Hermes rather than editing Nix; NixOS controls the image, network and secret
injection. To check the saved default and run a bounded provider test:

```sh
sudo docker exec hermes hermes config get model.default
sudo docker exec hermes hermes chat -Q --max-turns 2 --run-budget 90 \
  -q 'Reply exactly HERMES_OMNIROUTE_OK. Do not use tools.'
```

After editing a stored startup field, restart only `docker-hermes` in an idle
window and verify recovery. Its startup step fetches the latest values without
restarting OmniRoute or refreshing the fleet's OpNix secrets. Rotating the
service-account bootstrap token itself requires host reprovisioning; use the
checked deployment procedure and inspect its broader restart scope.

The official CLI from the locked nixpkgs input is mounted read-only into the
unchanged Hermes image. The `op` wrapper supplies the account token from its
private mount. Overseer can read and edit the Shulker vault through that account,
including server items. This is vault-wide authority, not item-level access.
Use `op run` or a subprocess to consume credentials without printing values.
Future agents need their own provisioning; they do not inherit this account.
Writing a stored value does not rotate the application credential: use the
application's supported API, save the new value and refresh the relevant client.

Configure the model and messaging with upstream Hermes commands:

```sh
sudo docker exec -it hermes hermes setup
sudo docker logs --tail 100 hermes
sudo systemctl restart docker-hermes
```

## Discord Overseer

Overseer uses the bundled Discord adapter in the existing Hermes container.
Enable `discord.enable` and set `discord.allowedUsers` to numeric Discord user
IDs. NixOS requires an explicit allowlist, requires mentions in server channels
and disables replies to other bots. Direct messages do not require a mention.

The startup renderer loads the bot token from the concealed **Discord environment**
field in the agent item's Hermes section. The field contains
`DISCORD_BOT_TOKEN=<token>`; keep its value out of Nix and Git. Activate the
bundled adapter through Hermes after provisioning the environment:

```sh
sudo docker exec hermes hermes plugins enable discord-platform
sudo systemctl restart docker-hermes
sudo docker exec hermes hermes plugins show discord-platform
```

Grant the bot messaging, history, attachment, reaction and thread permissions,
and enable Message Content and Server Members intents in Discord's developer
portal. Channel permissions determine where the bot can participate; dedicated
mention-free channels can be configured with Hermes' native
`discord.free_response_channels` setting. Shared channels can use mentions to
choose an agent. Future agents need their own bot credentials and isolated
Hermes state; bot collaboration must be enabled deliberately when they exist.

Before deployment, use an idle window and inspect the activation's restart scope.
Afterward, verify the Discord gateway
connects, send a DM and a channel mention, and check the replies. Inspect logs
through the private Hermes dashboard. An enabled plugin alone does not prove
that Discord messages are being received.

The built-in dashboard can inspect sessions and logs. There is one Hermes home
and one gateway. Knowledge publishing and coding delegation can be configured
later using upstream features. No custom gateway adapter is installed.
The state directory is persistent and included in the existing encrypted backups.
The retired installations remain in their old persistent directories for recovery.

## Engineer migration and validation

`engineer.enable` adds a separate `hermes-engineer` OCI container, owned by
`docker-hermes-engineer.service`. It reuses `/var/lib/hermes-engineer/data` and
`/var/lib/hermes-engineer/workspace` without seeding identity or overwriting
`config.yaml`. `engineer.allowedUsers` is an explicit numeric allowlist;
allow-all is false, server mentions are required and bot replies are disabled.
The module requires OmniRoute. Engineer shares its inference-only secret and
Docker bridge, not the dashboard, Overseer bot token or host administration.
There are no published ports, SSH/key mounts, Docker socket, vault token or
host workspace mounts. Both agents currently run as UID/GID 10000 inside their
separate containers; this is a mount boundary, not separate host Unix identities
or network isolation from peers on the OmniRoute bridge.

OpNix provisions the dedicated **[AI] Engineer** item's Hermes section field
**Discord Environment** (case-sensitive). It must contain only
`DISCORD_BOT_TOKEN=<token>`. The provider field must contain exactly one nonempty
`HERMES_OMNIROUTE_API_KEY=<key>` entry. The file-based startup renderer reuses the
strict Docker/dotenv parser and rejects missing, empty, malformed, duplicate or
extra keys in either source, including policy and administrative credentials.
Inspect key names privately before activation, not values. Only validated values
and the explicit NixOS Discord policy are atomically published to
`/run/hermes-engineer-managed/.env`, mode 0400, mounted read-only at
`/etc/hermes/.env`. Docker consumes that same validated file, never the raw vault
fields. A validation failure blocks startup without publishing a partial file.
The runtime file is regenerated on every start and is outside persistence and backups.
The full Engineer state directory is included in Borgmatic and, when the parent
`impermanence` option is enabled, `/nix/persist`. Treat state backups as private:
existing profile files can contain credentials and conversations.

Migration is a NixOS deployment, never a replacement `docker run`:

1. Use an approved idle maintenance window. Record the current Engineer image
   ID, mounts and enabled messaging platforms privately. Confirm the pinned
   module image resolves to the same image ID as the existing container before
   cutover; a local image ID is not a registry manifest digest. The known live
   ID at migration preparation was
   `sha256:373ddd5e6649f525b17993e1c885cdf1352127f8e98fd329140a73237125e52f`.
   The declaration deliberately retains the existing tested stable digest, not
   a new tag/version. If these differ, stop and resolve the pin without upgrading.
2. Before any snapshot or copy, disable the old container's autostart and stop
   the old Engineer container; verify it is stopped and no Engineer gateway is
   writing either state tree. Keep it stopped through copying and NixOS activation.
   Only then preserve a private consistent snapshot/backup of both state trees,
   including SQLite databases, and verify their owner is UID/GID 10000. Inspect
   `findmnt -T /var/lib/hermes-engineer` and the backing directory to determine
   whether the existing tree is already persistent before enabling the
   impermanence bind mount: a new empty backing directory must not hide live
   tmpfs state. If needed, copy the stopped tree with metadata preserved to
   `/nix/persist/var/lib/hermes-engineer` using the normal impermanence migration
   procedure, then verify the copy before activation. Do not restart the old
   container after the copy: further writes would diverge from persistent state.
   Never delete or reinitialize the live state. Existing model, identity and
   Discord plugin activation remain native Hermes state.
3. Validate with `nix flake check --no-build --all-systems`, build
   `.#nixosConfigurations.shulker.config.system.build.toplevel`, then use
   `sudo shulker-rebuild dry-activate --flake .#shulker`. Review the unit diff:
   Overseer's OCI declaration should be unchanged. Adding an OpNix secret and
   attaching Engineer to the provider secret changes OpNix's configuration and
   can restart Overseer, OmniRoute and other dependents. Do not promise a
   zero-interruption migration or restart OpNix casually.
4. At cutover only, confirm the old imperative container remains stopped with
   autostart disabled, then remove its container object without deleting
   bind-mounted state, so the NixOS OCI
   unit can own the same name. This is cleanup, not permission for an imperative
   deployment. Keep the private recovery record/backup. Advance through
   `sudo shulker-rebuild test --flake .#shulker`, validate, then
   `sudo shulker-rebuild switch --flake .#shulker`. Do not run two gateway
   processes against the same state or bot. If activation fails, stop the new
   unit and use a reviewed NixOS rollback/recovery; do not recreate a container
   imperatively. A rollback generation without Engineer does not manage it.

After activation, check the exact target without printing secret values:

```sh
sudo systemctl is-active docker-hermes-engineer docker-hermes docker-omniroute
sudo docker inspect hermes-engineer --format '{{.Image}} {{json .Mounts}} {{json .HostConfig.PortBindings}}'
sudo stat -c '%a %u:%g %n' /run/hermes-engineer-managed/.env
sudo docker exec hermes-engineer hermes gateway status
sudo docker exec hermes-engineer hermes config get model.default
sudo docker exec hermes-engineer hermes chat -Q --max-turns 3 --run-budget 90 \
  -q 'Identify yourself, then run python --version with your terminal tool and report the result.'
```

Confirm the image ID matches the pre-cutover ID; mounts are exactly Engineer's
state/workspace plus the read-only managed env; no ports or administrative
mounts exist. Check the managed env's key names only against the two approved
sources plus four Discord policy keys. Verify the gateway state/log privately
for the intended Engineer Discord identity and connected status. Confirm the
saved model, identity, sessions, memory and workspace survive. Verify the
Borgmatic sources and persistent backing directory, then inspect the next backup
and test restoration into an empty directory (never over live state). A generic
file backup during SQLite writes is not proof of a consistent database restore;
use a quiesced snapshot for migration recovery.

Finally have the allowed user send Engineer a real Discord DM and server
mention and confirm replies. A connected gateway, enabled plugin or bot-origin
message is not user-origin authorization verification. Confirm unsolicited
messages, other users and bot messages do not trigger replies. Keep deployments,
upgrades and future migrations declarative through NixOS.

## Overseer context and host access

`overseer.enable` seeds native identity, memory and workspace instructions once.
The files under `overseer/` are initial context, not templates reapplied over
learned state. Existing files are preserved, including an upstream starter
`SOUL.md`; replace that starter deliberately during initial activation, after
keeping a private recovery copy. New sessions load the updated context. Use
`/new` in Discord after setup; restarting the gateway alone does not reset a
conversation's memory snapshot.

Compact native memory lives in `data/memories/`; longer Markdown reports live in
`workspace/knowledge/`. Both are already covered by the Hermes backup directory.
The private Quartz site publishes the knowledge folder in its Overseer section;
compact memory remains available in Hermes. Memory and skill writes remain
enabled, while installation and host permissions remain managed by NixOS.

The `ssh shulker` alias uses a dedicated `hermes-operator` account, a verified
host key and a read-only private-key mount. Its private key is stored as a
concealed OpenSSH value in the agent item's **SSH / Private key** field. That
field is usable by the server but does not provide native desktop SSH-agent
features. Preserve the previous **overseer ssh** item through rollout acceptance.
Only public keys belong in the host configuration. The account has no direct
Docker, wheel or journal group membership; its SSH key disables forwarding.

The account has unrestricted passwordless sudo as root, as requested by Pierre.
Root authority can override host protections and read host secrets; private
mounts do not constrain it. Workspace instructions require an idle check for
routine restarts and approval for deployments, destructive operations, server
credential changes and host permissions. Agent credential records can be
maintained autonomously. Shulker uses sudo-rs and permits this non-wheel account
to invoke sudo. Context seeding runs
as the unprivileged Hermes user, so writable directory symlinks cannot redirect
root filesystem operations.

Validate root access with `ssh shulker 'sudo -n id -u'` (expected `0`) and inspect
`sudo -l`. Test
knowledge and native memory writes, and start a fresh Discord session to check
recall. Do not restart services merely to test permissions.
