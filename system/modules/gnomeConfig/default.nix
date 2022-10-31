{ config, lib, pkgs, ... }:

with lib;
let cfg = config.shulker.modules.gnomeConfig;
in
{
  options.shulker.modules.gnomeConfig = {
      enable = mkEnableOption "Gnome config (extensions, etc)";
      eyeCandy = mkEnableOption "Optional extensions for better visuals";
      moreUtils = mkEnableOption "More utilities extensions";
    };

  config = mkIf cfg.enable {
    system.packages = with pkgs.gnomeExtensions; [
      espresso # Disable autosuspend with a button
      lock-keys # Numlock & Capslock status on the panel
      just-perfection # Many options
      appindicator # Systray icons
      (mkIf cfg.eyeCandy {
        burn-my-windows # Cool animations
        dash-to-dock # Dock on dekstop
      })
      (mkIf cfg.moreUtils {
  	    vitals # CPU temp, etc
        clipboard-indicator # Clip board manager
        ssh-quick-connect # Quick SSH Menu
      })
    ];

    services.udev.packages = with pkgs; [ 
      gnome.gnome-settings-daemon 
    ];
  };
}
