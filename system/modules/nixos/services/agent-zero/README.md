# Agent Zero

Aegis's bounded Agent Zero trial uses the upstream Kali/XFCE image pinned to a
registry digest. NixOS owns container lifecycle; do not use in-product self-update
for the managed release. Writable user state is persisted and included in host
backups, separately from retained OpenClaw state.

Access is owner-only through Pangolin at `https://aegis.shulker.link`. Native
single-user login is disabled by explicit owner choice. This requires a verified
edge gate covering HTTP and realtime endpoints; the backend is published only on
loopback. Local host/container principals are not excluded by that edge gate.
Do not provide untrusted local users access to the runtime network.

Main and utility models initially share the existing dedicated OmniRoute key and
model route. Embeddings use the upstream local default. The container receives no
Docker socket, host operator SSH identity or host bootstrap credential. Root inside
the upstream container is not host administration authority. The separate Aegis
service-account credential is retained in 1Password, not injected into this trial.

Unit: `docker-aegis-agent-zero.service`. Verify a real model/tool task, reconnect
and retained files before judging readiness. Healthy HTTP alone is insufficient.
Back up user state before updates; restoring it is separate approved work. Stop
this unit to pause; retain state and credentials unless separately instructed.
Hermes Administrator remains the incumbent pending owner evaluation.
