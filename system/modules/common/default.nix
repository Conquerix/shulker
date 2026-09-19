{ lib, ... }:
{
  # Discover the cross-platform core module tree.
  imports = lib.custom.scanPaths ./.;
}
