{ lib, ... }:
{
  # Discover the application, development, and shell module groups.
  imports = lib.custom.scanPaths ./.;
}
