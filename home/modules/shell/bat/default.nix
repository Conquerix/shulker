{
  config,
  lib,
  pkgs,
  ...
}:

with lib;
let
  cfg = config.shulker.home.modules.shell.bat;
in
{
  options.shulker.home.modules.shell.bat = {
    enable = mkEnableOption "bat configuration";
  };

  config = mkIf cfg.enable {
    home.packages = [ pkgs.bat ];
  };
}
