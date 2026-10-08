# Hermes Trial

This opt-in service prepares one private Hermes assistant, Overseer, for
Conquerix. Its eventual role is maintaining Shulker and Hermes. The trial has
only a disposable workspace and its own provider/bot credentials. It does not
replace `hermes-agent`, migrate existing memory, or grant host administration.

## Configuration

`shulker.system.modules.hermes-trial.enable` defaults to false. Enable only after
reviewing the trial deployment. Supply `zulipUrl`, exactly one numeric ID in
`allowedUsers`, private channel IDs in `allowedChannels`, and `secretReference`
for a dedicated 1Password environment file. It contains `ZULIP_BOT_EMAIL`,
`ZULIP_API_KEY` and any approved integration credentials. Do not reuse the
production Hermes environment or the host opnix token.

The model provider is fixed to `openai-codex` for ChatGPT subscription access.
Supply `model` with an ID verified through the authenticated provider catalog.
No separately billed API fallback is configured. Complete a fresh device login
for this runtime with `hermes auth add openai-codex`; its renewable OAuth state
belongs in the private persistent home, not the injected environment file.
With the gateway stopped, use the pinned container with the same UID, home and
configuration mounts for login. Test a harmless inference before starting daily
use; successful login alone does not establish model entitlement. Reauthentication
may be needed after revocation or a terminal refresh failure.


Shulker resolves a dedicated agent item through opnix and injects its environment
file. Overseer receives the assigned service credentials; it receives no
1Password service-account token. Several agents can therefore use separate items
in the same deployment vault, with runtime access limited by host provisioning.
Routine service access works unattended once credentials are supplied. Adding
new credentials remains a host provisioning operation. Scope each credential's
permissions at the target service; read-only vault access does not make its API
keys read-only.

The container runs as UID/GID 10010. State is `/var/lib/hermes-trial/overseer/home`
and its disposable workspace is `/var/lib/hermes-trial/overseer/workspace`.
Enable `impermanence` on an ephemeral-root host. The root filesystem, plugin,
policy configuration and patched core file are read-only. Container limits are
2 GiB RAM, one CPU and 256 PIDs. It has no Docker socket or host SSH credentials.
Skills and memory can evolve within its state boundary; updating installed
Hermes or the adapter requires a reviewed source/image change.

## Messaging behavior

Use a private Overseer channel with one topic per task, or a direct message.
Numeric user IDs and explicit channel IDs gate inbound messages. Group DMs and
all slash commands are rejected in this first trial. This deliberately excludes
bulk approval, permission-mode and runtime-reconfiguration commands. React to
approval messages with thumbs-up for one request or thumbs-down to reject.
The full command must fit in a single prompt; oversized prompts are refused.
Request IDs, not queue order, bind decisions to pending commands.

Topic renames/moves invalidate their old and new destinations. Start a fresh
topic after checking effects of interrupted work. Old approval messages cannot
authorize a new request. Intake IDs are stored in `overseer-intake.sqlite`;
recovered or uncertain messages require an explicit resend and are never replayed.
An expired event queue invalidates known channel conversations because missed
move events cannot be reconstructed. Start a fresh topic in that case.
A failed history reconciliation pauses intake. These are application controls,
not a security boundary against arbitrary malicious code inside the same agent.
Permissions at the destination service remain authoritative.

## Operation and acceptance

Inspect `docker-hermes-overseer` and its bounded container logs. Do not publish
raw logs or credentials in the knowledge base. The separate dashboard project
remains the eventual recovery UI; this trial can be stopped from host systemd.
Stop only `docker-hermes-overseer` to roll back; preserve trial state and the
existing production Hermes service. Never start two writers against one home.

Before daily use, test real PocketID login, denied identities, locked-phone
notifications, approval expiry and restart, topic changes during work, and
completion after closing all clients. Confirm filesystem ownership and runtime
limits on Linux. Source tests do not establish these live properties. Test
restoration into an empty location before any state replacement.

## Maintenance

`upstream.nix` pins the verified source commit, archive hash and OCI digest.
`approval-request-id.patch` propagates the request identity into the adapter;
`plugin/UPSTREAM.md` identifies the MIT-licensed fork. Run the real-Hermes tests
through the `hermes-zulip-tests` flake check after every dependency update.
The enabled Nix fixture uses synthetic IDs and no real secrets; production
Shulker remains disabled until an explicit deployment change.
