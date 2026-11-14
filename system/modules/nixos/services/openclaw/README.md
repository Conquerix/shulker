# Openclaw

Aegis is a separate, unprivileged OpenClaw Gateway, pinned through nix-openclaw.
NixOS owns its lifecycle and immutable configuration; writable state and workspace
live under its persistent service directory and are included in host backups.
Administrator and OmniRoute remain independently deployed during qualification.

## Access and credentials

Native apps connect to `https://aegis.shulker.link`. Pangolin supplies TLS ingress;
OpenClaw supplies token authentication and explicit device pairing. Browser SSO
is not applied to this endpoint because native clients must use its WebSocket.
There is no direct public Gateway port. Device pairing does not authorize camera,
location, screen or local command execution; sensitive node commands are denied.

Gateway, inference and dedicated service-account credentials come from OpNix.
Never display them, put them into Nix-store configuration or export diagnostics
containing their values. The inference key is restricted to the configured model.
The agent's vault account has real upstream vault permissions, not a per-item
security boundary; operating instructions do not narrow its vault authority.

## Operations and recovery

Unit: `aegis.service`. Start with `systemctl status aegis`, Gateway health and a
real model turn. Exec uses ask mode and elevated mode is disabled. The initial
runtime has no root sudo, Docker socket or SSH operator identity; promotion to
host administration is a separate explicit step after read-only qualification.

Keep a consistent SQLite backup before upgrades. File persistence and backup
inclusion alone do not prove restoration; restore to an empty target and verify
with the matching CLI before relying on it. Stop Aegis before restoring live data.
Binary rollback does not undo schema migrations. Preserve the previous generation
and incumbent Administrator until Pierre accepts the handover.
