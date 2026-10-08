# Hermes Agent

Shulker runs one official Hermes container, including its built-in dashboard.
NixOS controls the image version and the `docker-hermes` service. Set `image`
to a tested tag/digest to upgrade; configuration remains editable inside Hermes.

Data is under /var/lib/hermes-clean/data, and the mounted workspace is under
/var/lib/hermes-clean/workspace. The dashboard listens on loopback port 23234
and is published privately through Pangolin at https://hermes.shulker.link.
Dashboard credentials are provisioned by OpNix from the Hermes section of the
shulker server item in 1Password. The container waits for secret provisioning;
the generated environment files are readable only by root. Hermes has its own
OmniRoute inference key in the same server item's Hermes section. OpNix injects
it into the container; native model configuration references the environment
variable, so the key never belongs in Nix or Git.

When OmniRoute is enabled on the host, both containers join the `omniroute`
Docker bridge. Hermes uses `http://omniroute:20128/v1` directly; the dashboard
remains private through Pangolin. The network permits outbound provider traffic.
Hermes' native `omniroute` provider uses Chat Completions, with
`cx/gpt-6.1-sol` as default and `cx/gpt-6-astra` also available. Its key is
restricted to those two models and cannot manage OmniRoute. Subscription
authentication stays in OmniRoute, with no paid API fallback.

Model settings remain in the writable data directory. Change them through
Hermes rather than editing Nix; NixOS controls the image, network and secret
injection. To check the saved default and run a bounded provider test:

```sh
sudo docker exec hermes hermes config get model.default
sudo docker exec hermes hermes chat -Q --max-turns 2 --run-budget 90 \
  -q 'Reply exactly HERMES_OMNIROUTE_OK. Do not use tools.'
```

After changing the stored provider environment, restart `opnix-secrets` to
reprovision it. Its required-service dependencies also restart Hermes and
OmniRoute, interrupting Hermes conversations and OpenHands or other gateway
requests. Use a window where both are idle, then check both container services
are active. The pre-integration model configuration is retained in the private
state directory for recovery.

Configure the model and messaging with upstream Hermes commands:

```sh
sudo docker exec -it hermes hermes setup
sudo docker logs --tail 100 hermes
sudo systemctl restart docker-hermes
```

The built-in dashboard can inspect sessions and logs. There is one Hermes home
and one gateway. Messaging, knowledge publishing and coding delegation can be
configured later using upstream features. No custom gateway adapter is installed.
The state directory is persistent and included in the existing encrypted backups.
The retired installations remain in their old persistent directories for recovery.
