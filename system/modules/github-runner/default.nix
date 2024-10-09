{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.modules.github-runner;
in
{
  options.shulker.modules.github-runner = {
    enable = mkEnableOption "Enable github runner service.";
    owner = mkOption {
      type = types.str;
      default = "conquerix/shulker";
      description = "Github owner of the runner.";
    };
    name = mkOption {
      type = types.str;
      default = "${config.networking.hostName}-${cfg.owner}-0";
      description = "Name of the runner instance.";
    };
    workDir = mkOption {
      type = types.str;
      default = "/var/lib/github-runner/workspace";
      description = "Working directory of the runner.";
    };
  };

  config = mkIf cfg.enable {

    services.github-runners."${cfg.name}" = {
      enable = true;
      tokenFile = "/secrets/github-runner-pat-token";
      url = "https://github.com/${cfg.owner}";
      name = cfg.name;
      user = "github-runner";
      group = "github-runner";
    };

    users.users.github-runner = {
      isSystemUser = true;
      createHome = true;
      home = cfg.workDir;
      group = "github-runner";
    };
    users.groups."github-runner" = { };

    #opsm.secrets = {
    #  github-runner-pat-token = {
    #    secretRef = "op://Shulker/Github Tokens/Runner PAT";
    #    user = "github-runner";
    #    mode = "0400";
    #  };
    #};
  };
}
