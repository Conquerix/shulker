{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.modules.dev.ocaml;
in
{
  options.shulker.modules.dev.ocaml = {
    enable = mkEnableOption "ocaml/emacs configuration";
  };

  config = mkIf cfg.enable {

    home.packages = with pkgs; [ ocaml ocamlPackages.lustre-v6 ocamlPackages.rdbg ocamlPackages.lutils ];

    programs.emacs = {
      enable = true;
      package = pkgs.emacs-gtk;
      extraPackages = epkgs: [
        epkgs.tuareg
      ];
    };
  };
}
