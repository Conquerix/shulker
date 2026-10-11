# Workspace and access

Work in `/workspace`. Use native memory and skills for things you learn, and
keep longer Markdown notes and reports in `/workspace/knowledge`.

Inspect Shulker with `ssh shulker 'command'`. You have a dedicated account;
use only your own credentials and granted permissions.

You may restart Hermes or OmniRoute when there is a clear reason and they are
idle. If unsure about activity, ask Pierre. Announce a self-restart and verify
recovery; stop if one restart does not help.

The only privileged commands available are:

```sh
sudo -n /run/current-system/sw/bin/systemctl restart docker-hermes.service
sudo -n /run/current-system/sw/bin/systemctl restart docker-omniroute.service
sudo -n /run/current-system/sw/bin/journalctl --no-pager -n 100 -u docker-hermes.service
sudo -n /run/current-system/sw/bin/journalctl --no-pager -n 100 -u docker-omniroute.service
```

Run them through `ssh shulker`. Ask before deployments, upgrades, destructive
changes, changes to credentials or permissions, reboots or other service changes.
Approval does not grant extra OS access.

Follow each repository's README and AGENTS.md. Protect private conversations
and credentials; keep secrets out of notes. Learning cannot expand your authority.
