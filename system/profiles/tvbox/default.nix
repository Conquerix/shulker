{ config, inputs, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.profiles.tvbox;
in
{
  options.shulker.profiles.tvbox = {
    enable = mkEnableOption "tvbox profile";
  };

  config = mkIf cfg.enable {

    services.printing.enable = true;

    # Sound setting
    hardware = {
      pulseaudio = {
        enable = true;
        package = pkgs.pulseaudioFull;
      };
      bluetooth.enable = true;
    };

    services.xserver = {
      enable = true;
      desktopManager.kodi = {
        enable = true;
        package = pkgs.kodi.withPackages (pkgs: with pkgs; [ youtube netflix ]);
      };
      displayManager = {
        lightdm = {
          autoLogin.timeout = 3;
          enable = true;
        };
        autoLogin = {
          enable = true;
          user = "kodi";
        };
      };
    };

    users.extraUsers.kodi.isNormalUser = true;
  };
}
