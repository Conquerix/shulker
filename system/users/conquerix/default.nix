{
  lib,
  ...
}:
{
  options.shulker.users.conquerix = {
    enable = lib.mkEnableOption "Enable conquerix' profile";
  };

  # Import the shared account and both branches; platform modules guard themselves.
  imports = [
    ./common.nix
    ./nixos.nix
    ./darwin.nix
  ];
}
