# Hermes Agent

Shulker runs one official Hermes container, including its built-in dashboard.
NixOS controls the image version and the `docker-hermes` service. Set `image`
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
