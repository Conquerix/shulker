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
      ];
    };

    services.printing.enable = true;

    # Sound setting
    sound.enable = lib.mkForce false;
    security.rtkit.enable = true;
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      jack.enable = true;
    };
    
    hardware = {
      pulseaudio = {
        #enable = true;
        enable = false;
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
      pamixer
      pavucontrol
      firefox-wayland
      qt6.qtwayland
      vlc
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
      displayManager.gdm.wayland = true;
      desktopManager.gnome.enable = true;
    };
    environment.gnome.excludePackages = (with pkgs; [
      gnome-photos
      gnome-tour
      gedit # text editor
    ]) ++ (with pkgs.gnome; [
      cheese # webcam tool
      gnome-music
      gnome-terminal
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
