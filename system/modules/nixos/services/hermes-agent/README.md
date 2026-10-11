# Hermes Agent

Shulker runs one official Hermes container, including its built-in dashboard.
NixOS controls the image version and the `docker-hermes` service. Set `image`
to a tested tag/digest to upgrade; configuration remains editable inside Hermes.

Data is under /var/lib/hermes-clean/data, and the mounted workspace is under
/var/lib/hermes-clean/workspace. The dashboard listens on loopback port 23234
and is published privately through Pangolin at https://hermes.shulker.link.
Dashboard credentials are provisioned by OpNix from the Hermes section of the
shulker server item in 1Password. The container waits for secret provisioning;
the generated environment files are readable only by root. Hermes has its own
OmniRoute inference key in the same server item's Hermes section. OpNix injects
it into the container; native model configuration references the environment
variable, so the key never belongs in Nix or Git.

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

After changing the stored provider environment, restart `opnix-secrets` to
reprovision it. Its required-service dependencies also restart Hermes and
OmniRoute, interrupting Hermes conversations and OpenHands or other gateway
requests. Use a window where both are idle, then check both container services
are active. The pre-integration model configuration is retained in the private
state directory for recovery.

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

OpNix loads the bot token from the concealed **Discord environment** field in
the Hermes section of the existing shulker server item. The field contains
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

Before deployment, use an idle window: reprovisioning OpNix can also restart
OmniRoute and its dependent clients. Afterward, verify the Discord gateway
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
Quartz publication is a separate future step. Memory and skill writes remain
enabled, while installation and host permissions remain managed by NixOS.

The `ssh shulker` alias uses a dedicated `hermes-operator` account, a verified
host key and a read-only private-key mount. Its key is stored in the dedicated
**overseer ssh** SSH Key item in the Shulker 1Password vault. The other Hermes
credentials remain in the shulker server item. Only public keys belong in the
host configuration. The account has no Docker, wheel or journal group membership
and cannot forward ports or agents.

Its only passwordless root commands are exact restarts and bounded journal reads
for `docker-hermes.service` and `docker-omniroute.service`. Normal accessible
host status can be inspected without sudo. The workspace instructions require
an idle check and prohibit other live changes without approval. Those
instructions guide behavior; the account and sudo grants enforce the actual
authority. Approval in chat does not grant deployment/root access automatically.
Shulker uses sudo-rs; its execution gate permits this non-wheel account to invoke
sudo, while its command rules retain the four exact grants. Context seeding runs
as the unprivileged Hermes user, so writable directory symlinks cannot redirect
root filesystem operations.

Validate access with `ssh shulker 'id; systemctl is-active docker-hermes.service
docker-omniroute.service'`, then inspect `sudo -l` and confirm a nonpermitted
command is rejected using sudo's list mode, which does not execute it. Test
knowledge and native memory writes, and start a fresh Discord session to check
recall. Do not restart services merely to test permissions.
