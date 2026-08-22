# Backup and restore

Borgmatic performs weekly repository checks and monthly archive checks. Test
the repository and inspect its archives manually after changing backup
configuration:

```sh
sudo borgmatic check --force
sudo borgmatic repo-list
```

Immich's snapshot hooks run inside Borgmatic's private device namespace. The
unit binds and permits only `/dev/zfs`, with `CAP_SYS_ADMIN` retained solely so
ZFS can create and destroy the guarded snapshot; do not disable the broader
device sandbox to make ZFS visible.

The backup module pins Hetzner Storage Box's published ED25519 host key in the
system-wide SSH known-hosts file. Keep that trust root declarative: verify any
future key change against Hetzner's independently published fingerprint before
updating the pin, rather than accepting a key interactively.

Borg authenticates with the host's persistent ED25519 key. After OpNix
provisions that private key, `sshd-keygen` and every SSH daemon start
atomically regenerate its adjacent public key; this prevents OpenSSH from
offering a stale `.pub` file during backup authentication.

Test file restoration into an empty temporary directory rather than over the
live filesystem:

```sh
restore_dir="$(mktemp -d)"
sudo borgmatic extract --archive latest --destination "$restore_dir" --path path/to/file
```

Database restoration is a separate, destructive operation. Use `borgmatic
restore --archive latest` only after validating the extracted backup and the
target database service.


## Related documentation

- [Operations](https://github.com/Conquerix/shulker/wiki/Operations)
- [Services](https://github.com/Conquerix/shulker/wiki/Services)
