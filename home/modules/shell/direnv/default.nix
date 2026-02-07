{
  config,
  lib,
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
  };
}
