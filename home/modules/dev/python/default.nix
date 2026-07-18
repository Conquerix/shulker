{
  config,
  lib,
  pkgs,
  ...
}:

with lib;
let
  cfg = config.shulker.home.modules.dev.python;

  extraPackages =
    p: with p; [
      pip
      setuptools
    ];

in
{
  options.shulker.home.modules.dev.python = {
    enable = mkEnableOption "python configuration";
  };

  config = mkIf cfg.enable {
    home.packages = with pkgs; [
      (python311.withPackages extraPackages)
      pipenv
    ];
  };
}
