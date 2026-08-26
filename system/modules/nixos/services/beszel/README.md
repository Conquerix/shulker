# Beszel

[Beszel](https://github.com/henrygd/beszel) provides the fleet's lightweight
server monitoring, historical metrics, container statistics, and alerts.
Shulker owns the hub at `https://monitor.shulker.link`; Enderdragon, Shulker,
Silverfish, and Warden run agents connected to that hub.

## Deployment and architecture

The service family has two native systemd roles:

- `beszel-hub.service` runs only on Shulker, stores the monitoring database in
  `/var/lib/beszel/hub`, and listens on host loopback. The repository-defined
  unit currently has no explicit service user, so it and its state are
  root-owned; changing that identity requires a state-ownership migration.
- `beszel-agent.service` runs on the four monitored servers. It uses a
  dedicated `beszel-agent` system user, can inspect systemd units over D-Bus,
  and enables SMART monitoring for local disks.

Agents receive their hub URL and credentials through environment variables.
The configured extra-filesystem labels cover `/nix` on every agent and
`/nix/persist` on the three hosts that expose that filesystem separately.
SMART support gives the agent elevated disk-inspection capabilities; changes
to those capabilities or device access require a security review.

The public hub options are `enable`, `impermanence`, `appUrl`, `stateDir`, and
`port`. Their defaults are disabled, `example.com`, `/var/lib/beszel/hub`, and
port 8080. Shulker overrides the URL and port with
`https://monitor.shulker.link` and 23232. The public agent options are
`enable`, `impermanence`, `stateDir`, `hubEndpoint`, and `extraFilesystems`;
enabled agents use `/var/lib/beszel/agent` and the public hub URL.

## Networking and exposure

The hub binds only to `127.0.0.1:23232`. Pangolin owns the public HTTPS route to
`monitor.shulker.link`; the host firewall is not the publication boundary for
that loopback listener. Agents are configured with the hub endpoint and the
wrapper does not open Beszel's agent firewall port. Do not add an inbound port
unless a reviewed Beszel architecture change requires it.

The hub's public URL, authentication, and Pangolin route must be checked in the
live control planes. Repository evaluation proves the loopback listener and
agent endpoint, but not the external route or account policy.

## State, secrets, and backups

Both hub and agent state directories are persisted when their role enables
`impermanence`; every currently enabled Beszel role does so. The hub state is
authoritative for monitoring history, dashboards, accounts, and alert
configuration. Agent state is local to each monitored host.

Agents use two logical 1Password secrets: `beszelAgentKeyFile` and
`beszelAgentTokenFile`. Each host receives its own files owned by the agent
user. Secret values and private identifiers must not enter Nix, logs, commits,
or documentation. Hub secrets: none are provisioned by this module; hub
accounts and authentication state live in its persistent application data.

The modules register `/var/lib/beszel/hub` and `/var/lib/beszel/agent` with
Borgmatic. Shulker, Enderdragon, and Warden currently enable off-host backups;
Silverfish does not, so its agent state is persistent but has no Borg archive.
There is no service-quiescing or application-export hook for Beszel in the
current backup module, so archives may capture live state and must be proven by
a restore rehearsal before they are treated as reliable recovery points.

## Health, change, and recovery

Use the commands appropriate to the host's role:

```sh
sudo systemctl status beszel-hub.service beszel-agent.service --no-pager
sudo journalctl -u beszel-hub.service --since today
sudo journalctl -u beszel-agent.service --since today
curl --fail http://127.0.0.1:23232/
```

Only Shulker has the hub listener. Final acceptance is in the Beszel UI: every
expected agent must be fresh, its filesystem labels must be correct, and SMART
data must be visible where supported. Absence of stale-agent or disk errors is
more useful than unit state alone.

For an upgrade, read the matching upstream release notes, validate the flake,
deploy the hub and one representative agent first, then confirm history,
metrics, alerts, systemd visibility, and SMART data before continuing. Agent
credential rotation is a live mutation and requires explicit approval.

For hub recovery, keep `beszel-hub.service` stopped, extract the Borg archive
into an empty disposable directory first, inspect it, then restore the complete
state directory with ownership and modes preserved and start a compatible
Beszel version. For an agent, prefer reprovisioning its host-specific
credentials and re-registering it when a trustworthy state archive is
unavailable. Destructive replacement of either live state directory requires
explicit approval.

## Related documentation

- [Services](https://github.com/Conquerix/shulker/wiki/Services)
- [Shulker host report](https://github.com/Conquerix/shulker/wiki/Host-shulker)
- [Public services](https://github.com/Conquerix/shulker/wiki/Public-Services)
- [Operations](https://github.com/Conquerix/shulker/wiki/Operations)
- [Backup and restore](https://github.com/Conquerix/shulker/wiki/Operations-Backup-and-Restore)
- [Security and recovery](https://github.com/Conquerix/shulker/wiki/Operations-Security-and-Recovery)
