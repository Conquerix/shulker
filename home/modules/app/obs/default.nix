{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.modules.app.obs;
in
{
  options.shulker.modules.app.obs = {
    enable = mkEnableOption "Open Broadcast Software";
  };

  config = mkIf cfg.enable {
    programs.obs-studio.enable = true;
  };
}
