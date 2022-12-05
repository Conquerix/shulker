{ config, lib, pkgs, ... }:

with lib;
let cfg = config.shulker.modules.shell.ssh;
in
{
  options.shulker.modules.shell.ssh = {
    enable = mkEnableOption "ssh configuration";
  };

  config = mkIf cfg.enable {
    programs.ssh = {
      enable = true;
      controlMaster = "auto";
      controlPath = "~/.ssh/control/%C";
      extraOptionOverrides = { "Include" = "~/.ssh/config.local"; };
      hashKnownHosts = true;
      extraConfig = '' IdentityAgent ~/.1password/agent.sock '';
    };
  };
}

