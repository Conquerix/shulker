{ config, lib, pkgs, ... }:

with lib;
let 
  cfg = config.shulker.modules.steam;
in
{
  options.shulker.modules.steam = { 
    enable = mkEnableOption "install steam correctly";
    protonGE = mkEnableOption "handle environment variables to detect manually installed Glorious Eggroll's proton versions";
  };

  config = mkIf cfg.enable {
    programs.steam = {
      enable = true;
      remotePlay.openFirewall = true; # Open ports in the firewall for Steam Remote Play
      dedicatedServer.openFirewall = true; # Open ports in the firewall for Source Dedicated Server
    };

    environment = mkIf cfg.protonGE {
        sessionVariables = rec {
          XDG_CACHE_HOME  = "\${HOME}/.cache";
          XDG_CONFIG_HOME = "\${HOME}/.config";
          XDG_BIN_HOME    = "\${HOME}/.local/bin";
          XDG_DATA_HOME   = "\${HOME}/.local/share";
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
      	protonup
      	protontricks
      	steam-tui
      ];
    };
  };
}
