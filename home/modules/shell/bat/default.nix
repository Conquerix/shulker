{ config, lib, pkgs, ... }:

with lib;
let cfg = config.shulker.modules.shell.bat;
in
{
  options.shulker.modules.shell.bat = {
    enable = mkEnableOption "bat configuration";
  };

  config = mkIf cfg.enable {
    home.packages = [ pkgs.bat ];
  };
}

