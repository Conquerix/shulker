{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.modules.dev.agda;
in
{
  options.shulker.modules.dev.agda = {
    enable = mkEnableOption "agda/emacs configuration";
  };

  config = mkIf cfg.enable {

    home.packages = with pkgs; [
      (agda.withPackages (p: [ p.standard-library ]))
    ];

    programs.emacs = {
      enable = true;
      package = mkForce pkgs.emacs-gtk;
      extraPackages = epkgs: [
        epkgs.agda2-mode
      ];
    };
  };
}
