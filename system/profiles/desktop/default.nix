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
      packages = with pkgs; [
        (
          nerdfonts.override {
            fonts = [ "JetBrainsMono" "Hack" "Meslo" "UbuntuMono" ];
          }
        )
        jetbrains-mono
      ];
    };

    services.printing.enable = true;

    # Sound setting
    security.rtkit.enable = true;
    hardware = {
      pulseaudio = {
        enable = true;
        package = pkgs.pulseaudioFull;
      };
      bluetooth = {
        enable = true;
        settings = {
          General = {
            Enable = "Source,Sink,Media,Socket";
          };
        };
      };
    };

    environment.systemPackages = with pkgs; [
      anytype
      pamixer
      pavucontrol
      firefox-wayland
      qt6.qtwayland
      vlc
    ];

    

    # Desktop environment
    services.xserver = {
      enable = true;
      xkb.layout = "fr";
      libinput = mkIf cfg.laptop {
        enable = true;
        touchpad.tapping = true;
      };
      displayManager.gdm.enable = true;
      displayManager.gdm.wayland = true;
      desktopManager.gnome.enable = true;
    };
    environment.gnome.excludePackages = (with pkgs; [
      gnome-photos
      gnome-tour
      gedit # text editor
      cheese # webcam tool
      gnome-terminal
      epiphany # web browser
      geary # email reader
      evince # document viewer
      totem # video player
    ]) ++ (with pkgs.gnome; [
      gnome-music
      gnome-characters
      tali # poker game
      iagno # go game
      hitori # sudoku game
      atomix # puzzle game
    ]);
  };
}
