# Discover service entry points; composite services import their own modules and helpers.
{ lib, ... }:
{
  imports = lib.custom.scanPaths ./.;
}
