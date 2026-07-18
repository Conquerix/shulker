# Shulker

Personal, flake-based Nix configuration for NixOS and nix-darwin. It manages
hosts, reusable system profiles and services, Home Manager configuration, and
1Password-backed secrets.

This repository is tailored to Conquerix's machines. Treat it as a reference,
not a drop-in configuration.

## Layout

- `system/hosts/` contains the machine-specific NixOS and Darwin entry points.
- `system/profiles/` groups reusable desktop, server, Steam Machine, and MacBook
  behavior.
- `system/modules/` contains reusable services and platform configuration.
- `system/users/` connects system users to their Home Manager configuration.
- `home/` contains shared Home Manager modules and defaults.
- `lib/`, `overlays/`, and `nix/` contain flake helpers, package overrides, and
  compatibility configuration.

The flake discovers host directories automatically. Each host imports its
hardware configuration and enables only the profiles and modules it needs.

## Hosts

NixOS: `enderdragon`, `endermite`, `guardian`, `phantom`, `shulker`,
`silverfish`, `warden`, and `wither`.

Darwin: `herobrine`.

## Common commands

```sh
# Evaluate every exported configuration and check.
nix flake check --no-build --all-systems

# Format the Nix sources.
nix fmt

# Enter the development shell with repository checks installed.
nix develop

# Apply a NixOS host configuration.
sudo nixos-rebuild switch --flake .#<host>

# Apply the Darwin configuration.
darwin-rebuild switch --flake .#herobrine
```

The NixOS configurations expect an opnix service-account token at
`/etc/opnix-token`. Secret values remain outside this repository.

Local login password hashes are also kept outside the repository. Provision
the required files before a fresh installation or before changing a local
password declaratively:

```sh
sudo install -d -m 0700 /etc/secrets
nix shell nixpkgs#mkpasswd -c sh -c \
  'mkpasswd -m yescrypt | sudo install -m 0600 /dev/stdin /etc/secrets/conquerix-password-hash'
```

Every NixOS host expects `conquerix-password-hash`; `endermite` additionally
expects `camelia-password-hash`. Existing mutable users keep their current
password if the corresponding file has not been provisioned yet.

## Origins

Originally forked from EmergentMind's
[nix-config](https://github.com/EmergentMind/nix-config) and since adapted to
this host and module layout.
