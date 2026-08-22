# Security and recovery

The NixOS configurations expect an opnix service-account token at
`/etc/opnix-token`. Secret values remain outside this repository.

Use `shulker-rebuild` for NixOS deployments. Before calling `nixos-rebuild`, it
evaluates the requested host from the prospective flake, reads the configured
token path, and asks OpNix to resolve every configured secret reference. The
resolved values exist only in a private temporary directory which is removed
before the rebuild begins. Failures report logical secret names, never values
or 1Password references. The first deployment can run the same wrapper with
`sudo nix run .#checked-rebuild -- ...`.

Rollbacks do not need this check. If 1Password is unavailable during an
emergency but the currently provisioned secrets are known to be usable, pass
`--skip-secret-check` explicitly. This is a recovery escape hatch; routine
deployments should remain fail-closed.

Local login password hashes are declared in the NixOS user configurations.
Users are immutable, so every activation restores the declared password. To
rotate a password, generate a yescrypt hash and replace the corresponding
`hashedPassword` value before rebuilding:

```sh
nix shell nixpkgs#mkpasswd --command mkpasswd -m yescrypt
```

This intentionally exposes the hashes through Git history and the Nix store,
allowing offline password cracking attempts. Use strong, unique passwords.
SSH password authentication remains disabled: the passwords provide console
and sudo access, while the configured keys provide key-only `conquerix` and
root recovery access.

## Touch ID-backed remote sudo

The macOS SSH client uses the 1Password SSH agent and forwards it only to
Pangolin SSH resources matching `*.ssh`. NixOS hosts accept an agent signature
for `sudo` and `sudo -i` when it matches a key in the root-owned
`/etc/ssh/authorized_keys.d/<user>` file. The private key and Touch ID data stay
on the Mac; password-based sudo remains available when the agent is absent or
locked.

In 1Password for Mac, enable **Settings -> Developer -> Use the SSH Agent** and
Touch ID. For tighter approval scope, configure the agent to ask for each new
application and terminal session and avoid **Approve for all applications**.
1Password may reuse an approval within the configured agent session, just as
sudo caches a successful authentication for a short period.

After applying the Darwin configuration and deploying a NixOS host, verify the
effective client policy and then force a fresh sudo authentication:

```sh
ssh -G warden.ssh | grep '^forwardagent yes$'
ssh warden
test -S "$SSH_AUTH_SOCK"
ssh-add -l
sudo -k
sudo true
```

Agent forwarding gives processes running as the connected remote user access
to the forwarded socket for the lifetime of that SSH session. Keep it scoped to
trusted hosts, close sessions when finished, and retain the independent console
password and root recovery keys.

Keep `users.mutableUsers = false`, the declarative password hashes, and the
independent SSH recovery keys unless deliberately changing the recovery model.
Generated documentation and diagnostic output must not expose secret values,
secret references, generated secret paths, password hashes, or service
credentials.

## Operational safety

Deployments, reboots, credential changes, destructive storage or database work,
and Git history rewrites can affect live systems or recovery. Confirm their
scope before running them.

Before restarting a gaming host or session, check for an active game and do not
interrupt it:

```sh
pgrep -f 'steamapps/[c]ommon'
```


## Related documentation

- [Operations](Operations)
- [Services](Services)
