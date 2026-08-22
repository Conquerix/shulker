# Hermes WebUI

Shulker runs the community
[Hermes WebUI](https://github.com/nesquena/hermes-webui) beside the existing
Hermes Agent gateway. The containers share Hermes state and workspace data; the
running Agent source is refreshed into an ephemeral, read-only WebUI mount on
each start. This follows the upstream two-container deployment without leaving
a stale named source volume after image updates. Browser-triggered tools execute
inside the WebUI container, while Telegram-triggered work continues in the
Hermes Agent container.

WebUI is published only on host loopback at `127.0.0.1:23234`. Pangolin should
expose that target as `https://hermes.shulker.link`. Do not open the port in the
host firewall or publish WebUI without its native authentication.

Create a `WebUI Environment` field in Shulker's existing Hermes 1Password item
containing:

```dotenv
HERMES_WEBUI_PASSWORD=<strong unique password>
```

After the secret exists, deploy the NixOS configuration and create a Pangolin
HTTP resource pointing to `http://127.0.0.1:23234`. Verify the service locally
before configuring a client:

```sh
curl --fail http://127.0.0.1:23234/health
```

For [Hermes Agent for macOS](https://github.com/hermes-webui/hermes-swift-mac),
select **Direct** connection mode and set the target URL to
`https://hermes.shulker.link`. The iOS client connects to the same WebUI service.
The browser interface is also installable directly as a PWA.

## Related documentation

- [Services](https://github.com/Conquerix/shulker/wiki/Services)
- [Shulker host report](https://github.com/Conquerix/shulker/wiki/Host-shulker)
- [Public services](https://github.com/Conquerix/shulker/wiki/Public-Services)
- [Operations](https://github.com/Conquerix/shulker/wiki/Operations)
- [Backup and restore](https://github.com/Conquerix/shulker/wiki/Operations-Backup-and-Restore)
- [Security and recovery](https://github.com/Conquerix/shulker/wiki/Operations-Security-and-Recovery)
