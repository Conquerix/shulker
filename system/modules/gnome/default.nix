{ config, lib, pkgs, ... }:

with lib;
let cfg = config.shulker.modules.gnome;
in
{
  options.shulker.modules.gnome = {
      enable = mkEnableOption "Gnome config (extensions, etc)";
      eyeCandy = mkEnableOption "Optional extensions for better visuals";
      moreUtils = mkEnableOption "More utilities extensions";
    };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs.gnomeExtensions; [
      espresso # Disable autosuspend with a button
      lock-keys # Numlock & Capslock status on the panel
      just-perfection # Many options
      appindicator # Systray icons
      
      (mkIf (cfg.eyeCandy) burn-my-windows) # Cool animations
      (mkIf (cfg.eyeCandy) dash-to-dock) # Dock on dekstop
      (mkIf (cfg.eyeCandy) alttab-mod) # Better Alt+Tab
      
      (mkIf (cfg.moreUtils) vitals) # CPU temp, etc
      (mkIf (cfg.moreUtils) clipboard-indicator) # Clip board manager
      (mkIf (cfg.moreUtils) ssh-quick-connect) # Quick SSH Menu
      (mkIf (cfg.moreUtils) quake-mode) # Drop down for any app
      
    ];

    services.udev.packages = with pkgs; [ 
      gnome.gnome-settings-daemon 
    ];
  };
}
