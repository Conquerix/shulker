{ config, lib, pkgs, ... }:

with lib;
let cfg = config.shulker.modules.app.discord;
in
{
  options.shulker.modules.app.discord = { enable = mkEnableOption "discord app"; };

  config = mkIf cfg.enable {
    home.packages = with pkgs;
      [
        # This is required to be from unstable as discord will sometimes soft-lock
        # on "there is an update" screen.
        discord
      ];
  };
}
