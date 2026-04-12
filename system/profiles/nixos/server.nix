{
  config,
  lib,
  ...
}:

with lib;
let
  cfg = config.shulker.system.profiles.server;
in
{
  options.shulker.system.profiles.server = {
    enable = mkEnableOption "server profile";
  };

  config = mkIf cfg.enable {

    networking = {
      dhcpcd.enable = false;
      networkmanager.enable = false;
      useNetworkd = true;
    };
    systemd.network = {
      enable = true;
      wait-online.enable = true;
    };
  };
}
