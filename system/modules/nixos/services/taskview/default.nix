# Assemble TaskView storage, runtime configuration, stack and backups.
{ ... }:
{
  imports = [
    ./backup.nix
    ./config.nix
    ./core.nix
    ./stack.nix
  ];
}
