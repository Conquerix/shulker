{ lib, ... }:
{
  # Discover user definitions from child directories.
  imports = lib.custom.scanPaths ./.;
}
