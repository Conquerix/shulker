{ config, inputs, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.profiles.desktop;
in
{
  options.shulker.profiles.desktop = {
    enable = mkEnableOption "desktop profile";
    laptop = mkEnableOption "Enable features for a laptop (trackpad, battery, etc...)";
  };

  config = mkIf cfg.enable {

    fonts.packages = with pkgs; [
      nerd-fonts.jetbrains-mono
      nerd-fonts.ubuntu-mono
      nerd-fonts.meslo-lg
      nerd-fonts.hack
      jetbrains-mono
    ];

    services.printing.enable = true;

    # Sound setting
    security.rtkit.enable = true;
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      jack.enable = true;
    };

    hardware.bluetooth = {
      enable = true;
      settings.General.Enable = "Source,Sink,Media,Socket";
    };

    environment.systemPackages = with pkgs.gnomeExtensions; [
      lock-keys # Numlock & Capslock status on the panel
      just-perfection # Many options
      appindicator # Systray icons
      gsconnect
      vitals
      burn-my-windows # Cool animations
      dash-to-dock # Dock on dekstop
      alttab-mod # Better Alt+Tab
      vitals # CPU temp, etc
      forge # Better windows tiling.
      pop-shell # Better than forge right above ?
      spotify-tray
      tailscale-qs
    ] ++ (with pkgs; [
      pamixer
      pavucontrol
      firefox-wayland
      qt6.qtwayland
      vlc
      gnome-themes-extra
      gnome-tweaks
      gtk-engine-murrine
      sassc
      okular
      pop-launcher
    ]);

    programs._1password-gui = {
      enable = true;
      polkitPolicyOwners = [ "conquerix" ];
    };

    programs.kdeconnect = {
      enable = true;
      package = pkgs.gnomeExtensions.gsconnect;
    };

    # Desktop environment
    services.libinput = mkIf cfg.laptop {
      enable = true;
      touchpad.tapping = true;
    };
    services.xserver = {
      enable = true;
      xkb.layout = "fr";
      displayManager.gdm.enable = true;
      displayManager.gdm.wayland = true;
      desktopManager.gnome.enable = true;
    };
    services.gnome.gnome-keyring.enable = lib.mkForce false;
    services.udev.packages = with pkgs; [ gnome-settings-daemon ];
    environment.gnome.excludePackages = with pkgs; [
      gnome-photos
      gnome-tour
      gedit # text editor 
      cheese # webcam tool
      gnome-terminal
      epiphany # web browser
      geary # email reader
      evince # document viewer
      totem # video player
      gnome-music
      gnome-characters
      tali # poker game
      iagno # go game
      hitori # sudoku game
      atomix # puzzle game
    ];
  };
}
