{
  config,
  lib,
  pkgs,
  ...
}:

with lib;
let
  cfg = config.shulker.home.modules.shell.ssh;
  onePasswordAgent =
    if pkgs.stdenv.isDarwin then
      ''"~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"''
    else
      "~/.1password/agent.sock";
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
      extraConfig = mkIf cfg._1password "IdentityAgent ${onePasswordAgent}";
      enableDefaultConfig = false;
      settings = {
        # Pangolin's SSH resource names are the only hosts trusted with agent
        # forwarding. OpenSSH evaluates this block again after canonicalizing
        # a short name such as `warden` to `warden.ssh`.
        "*.ssh" = mkIf cfg._1password {
          forwardAgent = true;
        };
        "*" = {
          canonicalizeHostname = true;
          canonicalDomains = [ "ssh" ];
          canonicalizeMaxDots = 0;
          canonicalizeFallbackLocal = true;
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
  };
}
