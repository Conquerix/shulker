{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.modules.gitea-actions-runner;
in
{
  options.shulker.modules.gitea-actions-runner = {
    enable = mkEnableOption "Enable gitea action runner service";
    url = mkOption {
      type = types.str;
      default = "example.com";
      description = "Url to the gitea instance.";
    };
    name = mkOption {
      type = types.str;
      default = "${config.networking.hostName}0";
      description = "Name of the runner instance";
    };
    labels = mkOption {
      type = types.listOf types.str;
      default = [ 
        "ubuntu-latest:docker://gitea/runner-images:ubuntu-latest"
        "ubuntu-22.04:docker://gitea/runner-images:ubuntu-22.04"
        "ubuntu-20.04:docker://gitea/runner-images:ubuntu-20.04"
      ];
      description = "List of labels that the runner can run.";
    };
    giteaHost = mkOption {
      type = types.str;
      default = config.networking.hostName;
      description = "Name of the host of the gitea instance";
    };
  };

  config = mkIf cfg.enable {

    services.gitea-actions-runner.instances."${cfg.name}" = {
      enable = true;
      tokenFile = "/secrets/gitea-runner-registration-token";
      url = cfg.url;
      name = cfg.name;
      labels = cfg.labels;
    };

    opsm.secrets = {
      gitea-runner-registration-token.secretRef = "op://Shulker/${cfg.giteaHost}/Gitea Runner Registration Token";
      user = "gitea-runner";
      mode = "0400";
    };
  };
}
