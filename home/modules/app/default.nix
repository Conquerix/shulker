{ lib, ... }:
{
  # Discover application modules from the child directories.
  imports = lib.custom.scanPaths ./.;
}
