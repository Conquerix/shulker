{
  config,
  lib,
  pkgs,
  ...
}:

with lib;
let
  cfg = config.shulker.system.profiles.macbook;
in
{
  options.shulker.system.profiles.macbook = {
    enable = mkEnableOption "macbook profile";
  };

  config = mkIf cfg.enable {
    security.pam.services.sudo_local.touchIdAuth = true;
    fonts.packages = with pkgs; [
      nerd-fonts.jetbrains-mono
      nerd-fonts.ubuntu-mono
      nerd-fonts.meslo-lg
      nerd-fonts.hack
      jetbrains-mono
    ];
  };
}
