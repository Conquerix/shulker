# Package the rebuild preflight with its tools, independent of the caller's PATH.
{
  opnix,
  pkgs,
}:
pkgs.writeShellApplication {
  name = "shulker-rebuild";
  runtimeInputs = [
    pkgs.coreutils
    pkgs.jq
    pkgs.nixos-rebuild
    pkgs.nix
    opnix
  ];
  text = builtins.readFile ../scripts/shulker-rebuild.sh;
}
