{
  lib,
  ...
}:
{
  options.shulker.users.conquerix = {
    enable = lib.mkEnableOption "Enable conquerix' profile";
  };

  imports = [
    ./common.nix
    ./nixos.nix
    ./darwin.nix
  ];
}
