{ lib, ... }:
{
  # Discover reusable NixOS role profiles in this directory.
  imports = lib.custom.scanPaths ./.;
}
