{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.modules.shell.direnv;
in
{
  options.shulker.modules.shell.direnv = {
    enable = mkEnableOption "direnv configuration";
  };

  config = mkIf cfg.enable {
    programs.direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

    shulker.modules.shell.bash.initExtra =
      mkIf config.shulker.modules.shell.bash.enable ''
        eval "$(direnv hook bash)"
      '';

    shulker.modules.shell.zsh.initExtra =
      mkIf config.shulker.modules.shell.zsh.enable ''
        eval "$(direnv hook zsh)"
      '';
  };
}
