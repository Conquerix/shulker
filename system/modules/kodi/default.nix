{ config, lib, pkgs, ... }:

with lib;
let cfg = config.shulker.modules.kodi;
in
{
  options.shulker.modules.kodi = {
      enable = mkEnableOption "Enable Kodi";
    };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs.gnomeExtensions; [
   	  kodi

    ];
}
