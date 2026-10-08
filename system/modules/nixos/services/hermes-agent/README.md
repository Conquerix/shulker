# Hermes Agent

Shulker runs one official Hermes container, including its built-in dashboard.
NixOS controls the image version and the `docker-hermes` service. Set `image`
to a tested tag/digest to upgrade; configuration remains editable inside Hermes.

Data is under /var/lib/hermes-clean/data, and the mounted workspace is under
/var/lib/hermes-clean/workspace. The dashboard listens on loopback port 23234
and is published privately through Pangolin at https://hermes.shulker.link.
Dashboard authentication is configured in the owner-only dashboard.env file
under the state directory. Model credentials belong in Hermes' data directory,
never in Nix or Git.

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
