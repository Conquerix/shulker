{ lib, ... }:
{
  # Discover the shared Home Manager core modules in this directory.
  imports = lib.custom.scanPaths ./.;
}
