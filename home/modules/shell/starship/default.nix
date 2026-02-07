{
  config,
  lib,
  pkgs,
  ...
}:

with lib;
let
  cfg = config.shulker.home.modules.shell.starship;
in
{
  options.shulker.home.modules.shell.starship = {
    enable = mkEnableOption "starship configuration";
  };

  config = mkIf cfg.enable {
    programs.starship = {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
      package = pkgs.starship;
    };
  };
}
