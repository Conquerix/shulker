{
  config,
  lib,
  pkgs,
  ...
}:

with lib;
let
  cfg = config.shulker.home.modules.shell.direnv;
in
{
  options.shulker.home.modules.shell.direnv = {
    enable = mkEnableOption "direnv configuration";
  };

  config = mkIf cfg.enable {
    programs.direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

    shulker.home.modules.shell.bash.initExtra = mkIf config.shulker.home.modules.shell.bash.enable ''
      eval "$(direnv hook bash)"
    '';

    shulker.home.modules.shell.zsh.initExtra = mkIf config.shulker.home.modules.shell.zsh.enable ''
      eval "$(direnv hook zsh)"
    '';
  };
}
