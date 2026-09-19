# Assemble storage, Compose runtime, operator bootstrap tools, and backup lifecycle.
{ ... }:
{
  imports = [
    ./backup.nix
    ./bootstrap.nix
    ./core.nix
    ./stack.nix
  ];
}
