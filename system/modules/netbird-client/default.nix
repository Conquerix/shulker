{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.modules.netbird.client;
in
{
  options.shulker.modules.netbird.client = {
    enable = mkEnableOption "Enable netbird daemon service";
  };

  config = mkIf cfg.enable {
    services.netbird.enable = true; # for netbird service & CLI
    environment.systemPackages = [ pkgs.netbird-ui ]; # for GUI
  };
}
