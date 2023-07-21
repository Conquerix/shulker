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

    services.xserver = {
      enable = true;
      desktopManager.kodi = {
        enable = true;
        package = pkgs.kodi-wayland.withPackages (pkgs: with pkgs; [ youtube netflix ]);
      };
      displayManager = {
        autoLogin = {
          enable = true;
          user = "kodi";
        };
      };
    };

    users.extraUsers.kodi.isNormalUser = true;
  };
}
