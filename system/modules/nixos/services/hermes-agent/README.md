# Hermes Agent

Administrator is the only deployed Hermes instance. NixOS owns its pinned image,
lifecycle, private credential wiring, independent SSH identity, persistence and
backups. Hermes owns its existing identity, configuration, sessions, skills and
memory. Activation must not reset them. Profiles alone are not security sandboxes.

## Runtime and access

Container `hermes-administrator` uses `/var/lib/hermes-administrator`, persisted
under `/nix/persist`. It has no Docker socket. Its own host account is
`hermes-administrator-operator` with passwordless root sudo. Host privileges do
not authorize changes. Discord permits only Pierre (`240780407442767873`), requires
server mentions and rejects bots. There is no public agent listener.

## Credentials and inference

OmniRoute remains solely as Administrator's inference backend on the private
Docker bridge. The default model is `cx/gpt-6.1-sol`; no paid fallback is added.
Preserve exact existing Discord/provider references and independent service-account
and SSH credentials. OpNix retrieves sources; the renderer validates exact key
sets and atomically publishes private runtime files. Never print credential values.

OpNix changes can restart Administrator and OmniRoute even when unit files are
unchanged. Execute self-affecting activation through a host-owned systemd unit
with explicit `PATH=/run/current-system/sw/bin`, and verify the unit journal and
active/default generation links after reconnecting. Initial settings bootstrap
absent state only. Use native Hermes configuration/plugin commands, not YAML edits.
OMH is pinned read-only; its writable state remains in Administrator's own data.

## Validation and recovery

Run `nix build .#checks.x86_64-linux.hermes-credentials-contract`,
`nix build .#checks.x86_64-linux.hermes-instances-contract`,
`nix flake check --no-build --all-systems`, and build the host toplevel.
After approved activation verify Administrator, OmniRoute, SSH, Newt, generation
links and a real model reply. Healthy containers alone are insufficient.
Backups contain private state; test restoration into an empty directory, not
live data. Preserve the backend image archive. No deployment is authorized by
this runbook.
