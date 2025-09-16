{
  config,
  lib,
  pkgs,
  ...
}:

with lib;
let
  cfg = config.shulker.home.modules.dev.nix;
in
{
  options.shulker.home.modules.dev.nix = {
    enable = mkEnableOption "nix configuration";
  };

  config = mkIf cfg.enable {
    home.packages = with pkgs; [
      # Source hash for fetchgit
      nix-prefetch-git
      # Source hash for github
      nix-prefetch-github
    ];
  };
}
