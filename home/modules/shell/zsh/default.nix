{
  config,
  lib,
  ...
}:

with lib;
let
  cfg = config.shulker.home.modules.shell.zsh;
in
{
  options.shulker.home.modules.shell.zsh = {
    enable = mkEnableOption "zsh configuration";
  };

  config = mkIf cfg.enable {
    programs.zsh = {
      enable = true;
      enableCompletion = true;
      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;

      # Declarative history config (replaces manual HIST* exports in initContent)
      history = {
        path = "$HOME/.zsh_history";
        size = 20000;
        save = 20000;
        share = true;
        ignoreDups = true;
        ignoreSpace = true;
        extended = true;
      };
    };
  };
}
