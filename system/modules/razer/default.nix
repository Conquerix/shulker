{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.system.modules.razer;
in
{
  options.shulker.system.modules.razer = {
    enable = mkEnableOption "Razer periperals support";
    batteryNotifier = mkEnableOption "Enable notifications on low battery";
  };

  config = mkIf cfg.enable {

    hardware.openrazer = {
      enable = cfg.enable;
      batteryNotifier.enable = cfg.batteryNotifier;
      users = [ "conquerix" ];
    };

    environment.systemPackages = with pkgs; [ razergenie polychromatic ];
  };
}
