{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.modules.app.libreoffice;
in
{
  options.shulker.modules.app.libreoffice = {
    enable = mkEnableOption "libreoffice, with spellcheck";
  };

  config = mkIf cfg.enable {
  	home.packages = with pkgs; [
  		libreoffice
  		hunspell
  		hunspellDicts.en_US
  		hunspellDicts.fr-any
  	];
  };
}
