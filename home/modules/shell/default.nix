{ lib, ... }:
{
  # Discover shell and terminal integration modules from child directories.
  imports = lib.custom.scanPaths ./.;
}
