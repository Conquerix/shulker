{ lib, ... }:
{
  # Discover the nix-darwin environment and networking modules.
  imports = lib.custom.scanPaths ./.;
}
