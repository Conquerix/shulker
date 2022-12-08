{ config, lib, pkgs, ... }:

with lib;
let cfg = config.shulker.modules.shell.zoxide;
in
{
  options.shulker.modules.shell.zoxide = {
    enable = mkEnableOption "zoxide configuration";
  };

  config = mkIf cfg.enable { home.packages = [ pkgs.zoxide ]; };
}
