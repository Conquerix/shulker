# Ollama

Wither runs [Ollama](https://ollama.com/) as a native CUDA-backed model
service. This module owns the NixOS service, its configured model list, local
state, and Borgmatic registration.

## Configuration and runtime

The public options are `enable`, `impermanence`, `port`, `host`,
`openFirewall`, and `stateDir`. Their defaults are disabled, port `11434`,
host `127.0.0.1`, a closed firewall, and `/var/lib/ollama`. Wither enables
impermanence and uses the native `ollama` service with `ollama-cuda`, a static
`ollama` user and group, and `DynamicUser = false`.

The module owns no container, proxy route, or secret. It stays loopback-bound
unless its public options are deliberately changed; opening the firewall is
not a substitute for a reviewed access and authentication design.

## State, backups, and recovery

`stateDir` stores Ollama models and data. When `impermanence` is enabled it is
persisted below `/nix/persist` with `ollama` ownership. The module contributes
that path to `backup.dirs`, but Wither does not enable Borgmatic, so its
evaluated Borgmatic source list is empty. There is no module-owned secret.

After an approved deployment, inspect `ollama.service`, its journal, and a
local request to the configured loopback API. Confirm that the intended models
are available and that CUDA use is appropriate for the host. Restore only from
an independently verified archive; otherwise redeploy and reload the declared
models.

## Related documentation

- [Services](https://github.com/Conquerix/shulker/wiki/Services)
- [Wither host report](https://github.com/Conquerix/shulker/wiki/Host-wither)
- [Backup and restore](https://github.com/Conquerix/shulker/wiki/Operations-Backup-and-Restore)
