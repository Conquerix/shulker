# Assemble Seafile modules explicitly; compose.nix is a shared factory, not a NixOS module.
{ ... }:
{
  imports = [
    ./backup.nix
    ./bootstrap.nix
    ./config.nix
    ./core.nix
    ./maintenance.nix
    ./stack.nix
  ];
}
