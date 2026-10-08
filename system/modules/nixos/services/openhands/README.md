# OpenHands

OpenHands adds an opt-in coding service beside Hermes Overseer. All components
are disabled by default. Shulker serves private Agent Canvas assets and a narrow
Unix-socket task broker; Enderdragon runs one fixed coding container. Neither
requires the laptop to remain connected. Local inference and automation are deferred.

## Configuration and placement

Enable `shulker.system.modules.openhands.frontend.enable` and `broker.enable` on
Shulker only, with the isolated Hermes trial enabled. The broker selects the
fixed native `overseer-coding` Agent Profile by UUID. Its referenced LLM Profile
can use any OpenHands-supported provider without changing Hermes or the broker.
Set `broker.secretReference` to a dedicated backend-key item field.
Enable `worker.enable` on Enderdragon only, with `worker.secretReference` pointing
to a private environment field containing `OH_SESSION_API_KEYS_0` and
`OH_SECRET_KEY`. Secret values are rendered at runtime, never embedded in Nix.
Missing/blank authentication causes startup failure; an empty upstream key list
would otherwise disable authentication.

Canvas 1.25.0 and Agent Server 1.53.0 are digest-pinned. Only the 2.7 MB static
Canvas layer is extracted on Shulker, without its execution/automation entrypoint.
The frontend is served at `/canvas/` through loopback port 23250; worker API port
23249 is also host-loopback only. Native Newt ingress must be reviewed separately.
The proposed private frontend hostname is `code.shulker.link`, protected by
Pangolin/PocketID for the owner, including assets and WebSockets. The proposed
machine API hostname is `coding-api.shulker.link`; use native session-key auth,
not interactive browser SSO in front of machine calls. Verify unauthorized HTTP
and WebSocket denial before publishing. No ingress is created by this module.

Frontend telemetry is disabled before its application scripts load. A restricted
CSP additionally blocks third-party telemetry connections. Build-generated hashes
permit only the pinned HTML's exact inline bootstrap scripts; arbitrary inline
scripts remain blocked. Worker telemetry is
opted out. Register the remote backend manually in Canvas with the owner's key;
no backend key is injected into HTML. A conversation link requires selecting
that registered backend in the browser. Browser backend keys live in that browser's
private storage; clear them when revoking access. Use first-message WebSocket
authentication; never place the key in a URL or proxy access log.

## Workspace, model login and limits

The worker has dedicated UID/GID 10011, 4 GiB RAM, 2 CPUs, 512 PIDs, a read-only
image, dropped capabilities and no-new-privileges. Its private Docker json-file
logs rotate at 10 MB across three files; that driver is selected explicitly because
the host default journald driver does not accept those rotation options. Its 512 MB
scratch tmpfs permits execution because the pinned PyInstaller server unpacks
executable libraries there; nosuid/nodev, container identity, mounts and caps
remain the boundary. Project builds already execute arbitrary project code. It has
no Docker/SSH/Nix-daemon socket, host home, infrastructure data or broad 1Password token. Its writable
mounts are `/var/lib/openhands` as `/state` and
`/srv/openhands/projects/shulker` as `/projects/shulker`. The native OpenHands
agent executes project tools directly within this container. Project files can execute
arbitrary build code inside this boundary; worktrees do not isolate shared Git
metadata or other files of the same project. Additional projects require their
own worker boundary. Docker access on the host remains administrator-only.

Place the approved repository at `/srv/openhands/projects/shulker/repository`.
The worker creates persistent worktrees below `/projects/shulker/worktrees`.
A declared host alias `/projects/shulker` resolves to the same project mount so
absolute Git worktree metadata also works from VS Code Remote SSH. Verify this
alias does not conflict with an existing path before deployment. Conquerix joins
the project group. State preparation grants that group write access to existing
project files and default ACLs on project directories, so new worktrees/files
remain editable through VS Code even under a restrictive tool umask. It does not
follow symlinks or apply those ACLs to provider state. Private
provider state remains 0700 and separate from the project group-accessible tree.
Conquerix's protected Git configuration trusts only this shared project subtree,
through both its host and container aliases, so Git accepts worker-owned worktrees
without globally disabling ownership checks. Inspect current RAM/storage usage before activation; Minecraft is not restarted
or displaced by this module's installation.

The coding agent is native OpenHands CodeAct. State preparation seeds one native
Agent Profile and an `overseer-coding` LLM Profile only when those files are absent;
subsequent deployments preserve operator edits. The agent starts with terminal,
file editor and task tracker tools, without saved project secrets, MCP connections
or automatic model-switching tools. Runtime mounts and identity contain tool
execution; Hermes approval callbacks do not approve OpenHands tool calls.

Initially the LLM Profile uses ChatGPT subscription authentication with Astra.
Connect ChatGPT directly under Canvas Settings → LLM → `overseer-coding`; the
native SDK owns OAuth login and refresh under `/state/settings/auth`. It does not
run Codex CLI or ACP. The pinned SDK's native subscription catalog currently lacks
GPT-6.1 Sol, GPT-6 Sol and GPT-6 Luna, so adding them requires a separately validated
SDK update. OpenAI model/provider names may still include “Codex”; that names the
subscription model service, not the coding agent. No paid API fallback is configured.

Use **Authentication → ChatGPT subscription**, rather than the separate LiteLLM
`chatgpt` provider. That legacy provider starts a synchronous device-code login
during metadata lookup, which can block the entire agent server. Its token
directory points to an absent path on the read-only root so it fails promptly;
native OpenHands OAuth retains its writable owner-only store. If an older worker
is stuck in that login, check active conversations, restart only the coding
worker, and reconnect through the native subscription control.

Select `overseer-coding` as the default Agent Profile in Canvas. Changing its LLM
Profile's provider, endpoint or model changes future tasks without changing the
coding agent. API credentials entered in Canvas are encrypted at rest using the
worker's secret key; subscription credentials have owner-only file permissions.
Existing conversations retain their original agent and history; start new native
conversations instead of resuming an old ACP conversation. Previous coding OAuth
state is retained for rollback and is not copied into the native credential store.
Hermes keeps its separate login. Native OpenVSCode is disabled; use desktop VS Code
Remote SSH for editing.

## Delegation and recovery

The root-installed Hermes tools are `coding_submit`, `coding_status`,
`coding_result` and `coding_pause`. Only approved Zulip gateway context is accepted;
CLI/environment fallback cannot impersonate the owner. Renamed/moved topics fail
closed. The model cannot select backend URL, credentials, agent profile, arbitrary paths,
settings or raw executor API. Results are untrusted project output. The broker's
full service key is a systemd credential and is never mounted in Hermes.

The broker owns one project lease at a time and records the core tool-call identity
before any mutation. It creates a conversation without an initial message, checks
the persistent workspace, then posts one message with `run=true`. Creating with
an initial message would auto-run and must not be followed by a second run.
A timeout/restart marks ambiguous work uncertain; retries do not resubmit it.
Status reconciles only the recorded conversation ID. `idle` is not completion;
`finished`, `error` and `stuck` are terminal. Paused/uncertain tasks retain their
lease. Direct browser owner actions bypass broker scheduling: coordinate them
with Hermes and VS Code; no promise of conflict-free simultaneous editing.

Use `journalctl -u openhands-broker`, `journalctl -u openhands-canvas` and
`journalctl -u docker-openhands-worker` for service health. Docker agent logs and
conversation state can contain private project output; do not publish raw logs.
If Enderdragon is offline, coding reports unavailable while Zulip and Overseer
remain independent. A pause is best-effort and neither undoes edits nor guarantees
that all spawned processes stop. Inspect the remote conversation/worktree before
retrying any uncertain task. Never clear a lease while that worker can still write.
An operator can stop the worker, inspect state and reconcile the journal with an
explicitly approved SQL update; no generic reset or replay endpoint is exposed.

## Backup, restore and rollback

Borgmatic hooks briefly stop the applicable worker/broker, archive private state,
then restart previously active services. A failed stop aborts and attempts recovery;
a failed restart reports operator action and does not replace the prior archive.
Worker backups include model/provider state and the entire project with Git
metadata; broker backups include the SQLite journal. Private archives are under
`/var/lib/openhands-backups` and belong only in encrypted private backups.
Do not dereference project symlinks into host paths. Agent keys and OAuth data must
never become knowledge-base files, shared reports or generated documentation.

Restore into an empty isolated destination, with writers stopped and outbound
model access blocked. Preserve project locations and the `/projects/shulker` alias
before testing Git worktree links. Treat restoring OAuth state separately: avoid
refreshing a copied rotating token in a second running agent. Verify archive
contents, repository/worktree links, SQLite integrity and conversation recovery;
local extraction is not proof of offsite retrieval or running-service recovery.
Credential rotation requires stopping the worker, regenerating its runtime config
and restarting it so the read-only config mount uses the new inode; restart the
broker to reload its separate systemd credential. These are approved live actions.

Rollback disables only new frontend/broker/worker units and their separately
provisioned ingress resources, while preserving project and provider state.
Existing production Hermes, Zulip and Minecraft remain separately managed.

## Validation

Focused checks: `openhands-contract`, `openhands-tests` and `openhands-assets`.
Real SDK tests run separately using the pinned SDK source's frozen uv lockfile,
with `OPENHANDS_TEST_SDK=1`, a disposable HOME and
`PYTEST_DISABLE_PLUGIN_AUTOLOAD=1`. The ordinary check explicitly skips those
SDK tests rather than pretending mocks validate the dependency. Live Linux image
startup, shared-editor ACL behavior on Linux, fresh subscription inference, private-browser/mobile access, end-to-end
Hermes submission and an empty-destination restore remain activation gates until
recorded as passing. No disabled module or unit test establishes them.
