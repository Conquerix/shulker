{
  config,
  lib,
  ...
}:

with lib;
let
  cfg = config.shulker.system.modules.sunshine;
in
{
  options.shulker.system.modules.sunshine = {
    enable = mkEnableOption "Enable sunshine game streaming service";
  };

  config = mkIf cfg.enable {

    services.sunshine = {
      enable = true;
      autoStart = true;
      capSysAdmin = true;
      openFirewall = true;
    };

    # Sunshine needs avahi for mDNS discovery by Moonlight clients on the LAN
    services.avahi = {
      enable = true;
      publish.enable = true;
      publish.userServices = true;
    };

    # Allow gamepad emulation for remote clients
    hardware.uinput.enable = true;
  };
}
