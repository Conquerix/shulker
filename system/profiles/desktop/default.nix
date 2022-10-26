{ config, inputs, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.profiles.desktop;
in
{
  options.shulker.profiles.desktop = {
    enable = mkEnableOption "desktop profile";

    laptop = mkOption {
      description = "Enable features for a laptop (trackpad, battery, etc...)";
      type = types.bool;
      default = false;
    };
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
    security.rtkit.enable = true;
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      # If you want to use JACK applications, uncomment this
      #jack.enable = true;
    };

    environment.systemPackages = with pkgs; [
      pamixer
      firefox
    ];

    hardware = { };

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
  };
}
