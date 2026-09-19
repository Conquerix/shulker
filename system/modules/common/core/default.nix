{ lib, ... }:
{
  # Discover core modules shared by NixOS and nix-darwin.
  imports = lib.custom.scanPaths ./.;
}
