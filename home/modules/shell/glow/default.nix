{
  config,
  lib,
  pkgs,
  ...
}:

with lib;
let
  cfg = config.shulker.home.modules.shell.glow;
in
{
  options.shulker.home.modules.shell.glow = {
    enable = mkEnableOption "glow configuration";
  };

  config = mkIf cfg.enable {
    home.packages = [ pkgs.glow ];
    xdg.configFile."glow".source = ../../../config/.config/glow;
  };
}
