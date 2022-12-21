{ config, lib, pkgs, ... }:

with lib;
let cfg = config.shulker.modules.docker;
in
{
  options.shulker.modules.docker = {
      enable = mkEnableOption "Enable docker tools";
    };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      docker-compose
      lazydocker
    ];

    virtualisation.docker = {
      enable = true;
      enableOnBoot = true;
    };
  };
}
