{ lib, ... }:
{
  # Discover reusable nix-darwin host profiles in this directory.
  imports = lib.custom.scanPaths ./.;
}
