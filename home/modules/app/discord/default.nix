{ config, lib, pkgs, ... }:

with lib;
let cfg = config.shulker.modules.app.discord;
in
{
  options.shulker.modules.app.discord = { enable = mkEnableOption "discord app"; };

  config = mkIf cfg.enable {
    home.packages = with pkgs;
      [
        (pkgs.discord.override {
          # remove any overrides that you don't want
          withOpenASAR = true;
          withVencord = true;
        })
        vesktop # For screen sharing with audio
      ];
  };
}
