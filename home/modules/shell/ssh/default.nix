{
  config,
  lib,
  pkgs,
  ...
}:

with lib;
let
  cfg = config.shulker.home.modules.shell.ssh;
in
{
  options.shulker.home.modules.shell.ssh = {
    enable = mkEnableOption "ssh configuration";
    _1password = mkEnableOption "Enable 1password identity agent";
  };

  config = mkIf cfg.enable {
    programs.ssh = {
      enable = true;
      extraOptionOverrides = {
        "Include" = "~/.ssh/config.local";
      };
      extraConfig = mkIf (cfg._1password) ''IdentityAgent ~/.1password/agent.sock '';
      matchBlocks."*" = {
        controlMaster = "auto";
        controlPath = "~/.ssh/control/%C";
        hashKnownHosts = true;
      };
    };
  };
}
