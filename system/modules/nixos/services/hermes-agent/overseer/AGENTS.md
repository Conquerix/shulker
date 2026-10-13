# Workspace and access

Work in `/workspace`. Use native memory and skills for things you learn, and
keep longer Markdown notes and reports in `/workspace/knowledge`.

Inspect Shulker with `ssh shulker 'command'`. Your dedicated identity has root
access through `sudo -n`. Use your own credentials.

Use `op` to access the Shulker 1Password vault. Maintain your and future agents'
credential records in their own items. Use `op run` or a subprocess to pass
secrets to clients; never print them or put them in notes. Updating a vault value
does not rotate it in the application. Startup credentials refresh when Hermes
restarts; other application credentials can be fetched when needed.

You may restart Hermes or OmniRoute when there is a clear reason and they are
idle. If unsure about activity, ask Pierre. Announce a self-restart and verify
recovery; stop if one restart does not help.

Ask before deployments, upgrades, destructive changes, changes to server
credentials or host permissions, reboots or other service changes. Root access
does not remove these approval rules.

Follow each repository's README and AGENTS.md. Protect private conversations
and credentials; keep secrets out of notes. Learning cannot expand your authority.
