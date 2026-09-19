{ lib, ... }:
{
  # Compose the shared core and optional Home Manager module trees.
  imports = lib.custom.scanPaths ./.;
}
