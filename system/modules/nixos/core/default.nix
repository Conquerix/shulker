{ lib, ... }:
{
  # Discover the NixOS baseline and cross-module assertions.
  imports = lib.custom.scanPaths ./.;
}
