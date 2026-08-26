# Newt

[Newt](https://github.com/fosrl/newt) is Pangolin's user-space tunnel client.
Shulker runs one client on Enderdragon, Shulker, Silverfish, and Warden so the
Pangolin control plane can reach services on those hosts through outbound
tunnels. Newt does not own public routes or authentication policy; those remain
live Pangolin configuration.

## Deployment and architecture

The Shulker module enables NixOS's native `services.newt` unit. It is not a
container. The unit starts at `multi-user.target`, reconnects automatically,
and currently points every enabled host at `https://proxy.shulker.link`.
Per-host client credentials are supplied at runtime through an environment
file, while the public endpoint remains declarative.

The wrapper sets `HOME` to the configured state directory and currently
disables the upstream dynamic-user mode without selecting a replacement user,
so the effective unit runs as root. Treat changes to the service user,
state-directory behavior, or Pangolin client identity as behavioral changes,
not as a mechanical module move.

The public module options are:

| Option | Default | Responsibility |
| --- | --- | --- |
| `enable` | `false` | Run the Newt systemd service. |
| `endpoint` | `example.com` | Pangolin endpoint used by the tunnel client. Every enabled host overrides it. |
| `stateDir` | `/var/lib/newt` | Newt's `HOME` and optional persistence target. |
| `impermanence` | `false` | Persist `stateDir` below `/nix/persist`. |

Keep `stateDir` at `/var/lib/newt` unless the underlying NixOS
`services.newt` state-directory declaration is changed and validated with it;
this wrapper alone does not relocate the upstream systemd `StateDirectory`.

## Networking and exposure

Newt initiates its connection to Pangolin. The module opens no host firewall
port and publishes no local HTTP health endpoint. A public hostname, target,
path rule, or authentication layer seen through the tunnel is Pangolin
control-plane state and must be inspected live before it is changed. Do not
infer that state from `endpoint` alone.

## State, secrets, and backups

The logical runtime secret is `newtEnv`, resolved from the enabled host's
1Password item. It contains the Pangolin client credentials expected by Newt.
Secret values and client identifiers must stay out of Nix, logs, commits, and
this runbook.

All currently enabled instances leave `impermanence` disabled, so this module
does not preserve `/var/lib/newt` across an ephemeral-root reboot. Backups:
none. The module does not register Newt state with Borgmatic. Recovery is
therefore based on the declarative endpoint plus reprovisioned 1Password
credentials, not on a Newt state archive.

## Health, change, and recovery

Check the unit and its recent connection log on the affected host:

```sh
sudo systemctl status newt.service --no-pager
sudo journalctl -u newt.service --since today
```

There is no module-owned local health URL. Acceptance requires confirming the
client is online in Pangolin and exercising at least one intended service
through that host's tunnel.

For a package or endpoint change, review the matching upstream release notes,
run the repository checks, deploy one host first, and verify reconnection and
one real route before continuing. Credential rotation is a separate live
mutation and requires explicit approval. To recover an instance, restore or
rotate its protected client credentials as appropriate, redeploy the host, and
repeat the Pangolin and end-to-end route checks; do not copy credentials from
another host.

## Related documentation

- [Services](https://github.com/Conquerix/shulker/wiki/Services)
- [Public services](https://github.com/Conquerix/shulker/wiki/Public-Services)
- [Operations](https://github.com/Conquerix/shulker/wiki/Operations)
- [Security and recovery](https://github.com/Conquerix/shulker/wiki/Operations-Security-and-Recovery)
