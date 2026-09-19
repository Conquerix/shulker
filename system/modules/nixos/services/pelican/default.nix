# Expose the web panel and Wings game-server node as independently enabled services.
{ ... }:
{
  imports = [
    ./panel.nix
    ./wings.nix
  ];
}
