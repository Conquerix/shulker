{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.modules.pterodactyl.manage;
in
{
  options.shulker.modules.pterodactyl.manage = {
    enable = mkEnableOption "Enable Pterodactyl utils to manage minecraft servers";
    dataDir = mkOption {
      type = types.str;
      description = mdDoc ''
        The directory with the management files.
      '';
      default = "/srv/server-management";
    };
  };
  
  config = mkIf cfg.enable {

    environment = {
      systemPackages = with pkgs; [
        packwiz
        mcman
      ];
      persistence."/nix/persist".directories = mkIf (config.shulker.modules.impermanence.enable) [ 
        "${cfg.dataDir}"
      ];
    };
  };
}
