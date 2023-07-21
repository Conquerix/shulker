{ config, lib, pkgs, ... }:

with lib;
let cfg = config.shulker.modules.gnome;
in
{
  options.shulker.modules.gnome = {
      enable = mkEnableOption "Gnome config (extensions, etc)";
    };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs.gnomeExtensions; [
      lock-keys # Numlock & Capslock status on the panel
      just-perfection # Many options
      appindicator # Systray icons
      gsconnect
      dynamic-panel-transparency
      vitals
      burn-my-windows # Cool animations
      dash-to-dock # Dock on dekstop
      alttab-mod # Better Alt+Tab
      aylurs-widgets # Beatiful widgets
      vitals # CPU temp, etc
      
    ] ++ [
      pkgs.gnome.gnome-themes-extra
      pkgs.gnome.gnome-tweaks
      pkgs.gtk-engine-murrine
      pkgs.sassc
      pkgs.okular
    ];

    services.udev.packages = with pkgs; [ 
      gnome.gnome-settings-daemon 
    ];

    services.gnome.gnome-keyring.enable = lib.mkForce false;

    programs.kdeconnect = {
    	enable = true;
    	package = pkgs.gnomeExtensions.gsconnect;
    };
  };
}
