{
  config,
  lib,
  pkgs,
  ...
}:

with lib;
let
  cfg = config.shulker.system.modules.steam;
in
{
  options.shulker.system.modules.steam = {
    enable = mkEnableOption "install steam correctly";
    protonGE = mkEnableOption "handle environment variables to detect manually installed Glorious Eggroll's proton versions";
    remotePlay = mkEnableOption "open the Steam Remote Play firewall ports";
    dedicatedServer = mkEnableOption "open the Source dedicated-server firewall ports";
  };

  config = mkIf cfg.enable {
    programs.steam = {
      enable = true;
      remotePlay.openFirewall = cfg.remotePlay;
      dedicatedServer.openFirewall = cfg.dedicatedServer;
      # Steam Input can't inject input into Wayland sessions via XTEST; extest
      # translates it. Needed for controller-as-mouse on the desktop (see
      # ValveSoftware/steam-for-linux#13251).
      extest.enable = true;
    };

    # The stock Valve hidraw rules match ATTRS{idVendor}=="28de", which only
    # exists on USB-parented devices — a Steam Controller paired over
    # Bluetooth never matches, so Steam can't open its hidraw node. Valve's
    # own rules add this BT device-path match; needed for the 2026 Steam
    # Controller (ValveSoftware/steam-for-linux#13251).
    services.udev.extraRules = ''
      KERNEL=="hidraw*", KERNELS=="*28DE:*", MODE="0660", TAG+="uaccess"
    '';

    environment = mkIf cfg.protonGE {
      sessionVariables = rec {
        XDG_CACHE_HOME = "\${HOME}/.cache";
        XDG_CONFIG_HOME = "\${HOME}/.config";
        XDG_BIN_HOME = "\${HOME}/.local/bin";
        XDG_DATA_HOME = "\${HOME}/.local/share";
        # Steam needs this to find Proton-GE
        STEAM_EXTRA_COMPAT_TOOLS_PATHS = "\${HOME}/.steam/root/compatibilitytools.d";
        # note: this doesn't replace PATH, it just adds this to it
        PATH = [
          "\${XDG_BIN_HOME}"
        ];
        # For HiDPI
        #GDK_SCALE = "2";
      };
      systemPackages = with pkgs; [
        steamtinkerlaunch
        protonup-ng
        protontricks
      ];
    };
  };
}
