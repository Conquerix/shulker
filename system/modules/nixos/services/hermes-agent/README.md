# Hermes Agent

Hermes Agent is the private automation gateway. Shulker deploys both the Agent
and WebUI containers. Its Telegram control surface continues work in the Agent
container, while the optional community
[Hermes WebUI](https://github.com/nesquena/hermes-webui) provides the browser,
PWA, and native-client backend from a separate container. Browser-triggered
tools run in the WebUI container. Keep Telegram private: the declarative
configuration disallows unrestricted users, requires mentions, and disables
guest mode.

## Architecture and exposure

The Agent container owns the gateway and persistent Hermes data. When WebUI is
enabled, it depends on the Agent, shares the Hermes state and workspace, and
receives a refreshed copy of the running Agent source through an ephemeral,
read-only mount at every start. This avoids a stale named source volume after
an image update.

The WebUI binds only to host loopback. Pangolin is the external exposure layer:
it should route the configured loopback target over authenticated HTTPS. Do not
open the WebUI port in the host firewall or expose it without its native
authentication.

Declarative source facts are the `hermes-agent` option namespace, the
`hermesAgentEnv` and `hermesWebUiEnv` logical secrets, and the configured WebUI
bind address, port, and public URL. Pangolin resources, domains, account
membership, and client enrolment are live account facts; inspect them in their
respective control planes rather than inferring them from this repository.

## Clients

Use the authenticated WebUI in a browser or install it as a PWA. For
[Hermes Agent for macOS](https://github.com/hermes-webui/hermes-swift-mac),
choose **Direct** connection mode and use the configured public HTTPS URL. The
iOS client uses the same WebUI endpoint. These clients require the WebUI to be
enabled and its Pangolin route to be healthy; Telegram remains an independent,
private Agent control surface.

## State, secrets, and backups

Persistent state is rooted at the configured Hermes state directory. It holds
the shared Hermes data, the WebUI state, the Agent home, and the workspace;
the read-only Agent source copy is deliberately ephemeral. With impermanence
enabled, the state directory is persisted with the Hermes service identity.

`hermesAgentEnv` supplies the Agent gateway environment, including Telegram
credentials and allowed-user policy. `hermesWebUiEnv` supplies WebUI-native
authentication. Store values only in the configured secret provider; do not add
them to Nix, this runbook, shell history, or tickets.

The backup boundary is the complete configured Hermes state directory. The
service adds that directory to the repository backup inputs; restoring it is a
stateful recovery operation and must follow the fleet backup-and-restore
procedure rather than overwrite live data.

## Health, changes, and recovery

After a declared configuration change, build and deploy through the approved
host workflow. Confirm the Agent and, when enabled, WebUI container services
are active. From the host, check the configured loopback target before changing
Pangolin or clients:

```sh
curl --fail http://127.0.0.1:23234/health
```

For a public-access failure, distinguish the layers: first verify local WebUI
health, then the Pangolin resource and authenticated route, then the client
account or device configuration. For Agent failures, inspect the Agent service
and its logical secret availability without revealing values. If state is
damaged, stop before overwriting it, validate a restore into an empty temporary
location, and use the documented backup recovery procedure. The service-state
preparation unit repairs ownership and removes only Hermes' obsolete managed
marker; it does not replace OAuth, Telegram, memory, or session state.

## Related documentation

- [Services](https://github.com/Conquerix/shulker/wiki/Services)
- [Shulker host report](https://github.com/Conquerix/shulker/wiki/Host-shulker)
- [Public services](https://github.com/Conquerix/shulker/wiki/Public-Services)
- [Operations](https://github.com/Conquerix/shulker/wiki/Operations)
- [Backup and restore](https://github.com/Conquerix/shulker/wiki/Operations-Backup-and-Restore)
- [Security and recovery](https://github.com/Conquerix/shulker/wiki/Operations-Security-and-Recovery)
