# Sunshine

Wither runs [Sunshine](https://app.lizardbyte.dev/Sunshine/) as its native
game-streaming host for Moonlight clients. This module owns the NixOS Sunshine
service integration and the host capabilities needed for discovery and virtual
gamepad input.

## Configuration and runtime

The public options are `enable` and `openFirewall`; both default to disabled.
Wither enables Sunshine and its Moonlight firewall setting. The module enables
Sunshine auto-start and `CAP_SYS_ADMIN`, publishes user services through
Avahi for LAN discovery, and enables uinput for remote gamepad emulation. It
does not use a container.

This is direct game-streaming access, not an independently declared public
web route. The module declares no proxy, DNS, external authentication policy,
or separate public endpoint. Keep firewall changes scoped to the intended
Moonlight clients and validate them with the host's network policy.

## State, secrets, backups, and recovery

The module declares no persistent state directory, Borgmatic input, or
logical secret. It does not create an independent backup responsibility.
Sunshine pairing and client state must be treated as runtime-managed data;
do not add credentials or client identifiers to Nix or documentation.

After an approved deployment, check the Sunshine unit and journal, then test
LAN discovery, pairing, controller input, video, and audio from an intended
Moonlight client. Before changing graphics, display, firewall, or streaming
settings, preserve a known-good connection path. Recovery is normally a return
to the prior declarative generation followed by a fresh client pairing check.

## Related documentation

- [Services](https://github.com/Conquerix/shulker/wiki/Services)
- [Wither host report](https://github.com/Conquerix/shulker/wiki/Host-wither)
- [Security and recovery](https://github.com/Conquerix/shulker/wiki/Operations-Security-and-Recovery)
