{
  config,
  lib,
  pkgs,
  ...
}:

with lib;
let
  cfg = config.shulker.home.modules.shell.zoxide;
in
{
  options.shulker.home.modules.shell.zoxide = {
    enable = mkEnableOption "zoxide configuration";
  };

  config = mkIf cfg.enable { home.packages = [ pkgs.zoxide ]; };
}
