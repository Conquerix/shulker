{
  config,
  lib,
  ...
}:

with lib;
let
  cfg = config.shulker.home.modules.app.ghostty;
in
{
  options.shulker.home.modules.app.ghostty = {
    enable = mkEnableOption "ghostty app";
  };

  config = mkIf cfg.enable {
    programs.ghostty = {
      enable = true;
      enableZshIntegration = true;
      installBatSyntax = true;
    };
  };
}
