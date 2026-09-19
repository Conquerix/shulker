{ lib, ... }:
{
  # Discover the nix-darwin core module tree.
  imports = lib.custom.scanPaths ./.;
}
