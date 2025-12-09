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
      enableDefaultConfig = false;
      matchBlocks."*" = {
        controlMaster = "no";
        controlPath = "~/.ssh/master-%r@%n:%p";
        hashKnownHosts = true;
        forwardAgent = false;
        addKeysToAgent = "no";
        compression = false;
        serverAliveInterval = 0;
        serverAliveCountMax = 3;
        userKnownHostsFile = "~/.ssh/known_hosts";
        controlPersist = "no";
      };
    };
  };
}
