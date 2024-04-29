{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.modules.dev.python;
  configHome = config.xdg.configHome;
  dataHome = config.xdg.dataHome;

  extraPackages = p: with p; [
    pip
    setuptools
  ];
  
in
{
  options.shulker.modules.dev.python = {
    enable = mkEnableOption "python configuration";
  };

  config = mkIf cfg.enable {
    home.packages = with pkgs; [
      (python311.withPackages extraPackages)
      pipenv
    ];
  };
}
