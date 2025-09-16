{
  config,
  lib,
  pkgs,
  ...
}:

with lib;
let
  cfg = config.shulker.home.modules.shell.xdg;
in
{
  options.shulker.home.modules.shell.xdg.enable = mkEnableOption "xdg configuration";

  config = mkIf cfg.enable {
    xdg = {
      enable = true;
      mime.enable = true;
    };
  };
}
