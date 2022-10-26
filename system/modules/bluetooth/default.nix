{ config, lib, pkgs, ... }:

with lib;
let cfg = config.shulker.modules.bluetooth;
in
{
  options.shulker.modules.bluetooth.enable = mkEnableOption "Bluetooth";

  config = mkIf cfg.enable {
    hardware.bluetooth.enable = true;

    services.blueman.enable = true;
  };
}
