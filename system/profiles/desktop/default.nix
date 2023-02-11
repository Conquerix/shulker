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

    fonts = {
      fonts = with pkgs; [
        (
          nerdfonts.override {
            fonts = [ "JetBrainsMono" "Hack" "Meslo" "UbuntuMono" ];
          }
        )
      ];
    };

    services.printing.enable = true;

    # Sound setting
    hardware = {
      pulseaudio = {
        enable = true;
        package = pkgs.pulseaudioFull;
      };
      bluetooth.enable = true;
    };

    environment.systemPackages = with pkgs; [
      pamixer
      pavucontrol
      firefox-wayland
      qt6.qtwayland
    ];

    

    # Desktop environment
    services.xserver = {
      enable = true;
      layout = "fr";
      libinput = mkIf cfg.laptop {
        enable = true;
        touchpad.tapping = true;
      };
      displayManager.gdm.enable = true;
      desktopManager.gnome.enable = true;
    };
    environment.gnome.excludePackages = (with pkgs; [
      gnome-photos
      gnome-tour
    ]) ++ (with pkgs.gnome; [
      cheese # webcam tool
      gnome-music
      gnome-terminal
      gedit # text editor
      epiphany # web browser
      geary # email reader
      evince # document viewer
      gnome-characters
      totem # video player
      tali # poker game
      iagno # go game
      hitori # sudoku game
      atomix # puzzle game
    ]);
  };
}
