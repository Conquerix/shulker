{
  lib,
  ...
}:
{
  options.shulker.users.conquerix = {
    enable = lib.mkEnableOption "Enable conquerix' profile";
    nixos = lib.mkEnableOption "Enable if on nixos";
    darwin = lib.mkEnableOption "Enable if on darwin";
  };

  imports = [
    ./common.nix
    ./nixos.nix
    ./darwin.nix
  ];
}
