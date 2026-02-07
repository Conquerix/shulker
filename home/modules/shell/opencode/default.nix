{
  config,
  lib,
  ...
}:

with lib;
let
  cfg = config.shulker.home.modules.shell.opencode;
in
{
  options.shulker.home.modules.shell.opencode = {
    enable = mkEnableOption "opencode configuration";
  };

  config = mkIf cfg.enable {
    programs.opencode = {
      enable = true;
      settings = {
        model = "anthropic/claude-opus-4-6";
        small_model = "anthropic/claude-sonnet-4-5";
        autoupdate = true;
      };
    };
  };
}
