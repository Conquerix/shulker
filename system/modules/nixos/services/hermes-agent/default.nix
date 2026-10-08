# One upstream Hermes container, including its built-in dashboard.
{ config, lib, ... }:
let
  cfg = config.shulker.system.modules.hermes-agent;
in
{
  options.shulker.system.modules.hermes-agent = {
    enable = lib.mkEnableOption "Hermes Agent";
    impermanence = lib.mkEnableOption "persistent Hermes data";
    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/hermes-clean";
    };
    image = lib.mkOption {
      type = lib.types.str;
      default = "docker.io/nousresearch/hermes-agent:stable@sha256:9774f4f39a9bb8c2f68ce728ed5e99ddbad282163be56764afacf88ed952b784";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 23234;
    };
    publicUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://hermes.shulker.link";
    };
  };
  config = lib.mkIf cfg.enable {
    shulker.system.modules.containers.enable = true;
    users.groups.hermes.gid = 10000;
    users.users.hermes = {
      isSystemUser = true;
      uid = 10000;
      group = "hermes";
    };
    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0700 hermes hermes -"
      "d ${cfg.stateDir}/data 0700 hermes hermes -"
      "d ${cfg.stateDir}/workspace 0700 hermes hermes -"
    ];
    virtualisation.oci-containers.containers.hermes = {
      image = cfg.image;
      pull = "missing";
      cmd = [
        "gateway"
        "run"
      ];
      ports = [ "127.0.0.1:${toString cfg.port}:9119" ];
      volumes = [
        "${cfg.stateDir}/data:/opt/data:rw"
        "${cfg.stateDir}/workspace:/workspace:rw"
      ];
      environment = {
        HERMES_UID = "10000";
        HERMES_GID = "10000";
        HERMES_DASHBOARD = "1";
        HERMES_DASHBOARD_HOST = "0.0.0.0";
        API_SERVER_ENABLED = "true";
        API_SERVER_HOST = "127.0.0.1";
        TERMINAL_CWD = "/workspace";
      };
      environmentFiles = [ config.services.onepassword-secrets.secrets.hermesDashboardEnv.path ];
      extraOptions = [
        "--memory=4g"
        "--cpus=2"
        "--pids-limit=512"
      ];
    };
    services.onepassword-secrets.secrets.hermesDashboardEnv = {
      reference = "op://Shulker/${config.networking.hostName}/Hermes/Dashboard environment";
      services = [ "docker-hermes" ];
      mode = "0400";
    };
    systemd.services.docker-hermes = {
      requires = [ "opnix-secrets.service" ];
      unitConfig.RequiresMountsFor = [ cfg.stateDir ];
    };
    environment.persistence = lib.mkIf cfg.impermanence {
      "/nix/persist".directories = [
        {
          directory = cfg.stateDir;
          mode = "0700";
          user = "hermes";
          group = "hermes";
        }
      ];
    };
    shulker.system.modules.backup.dirs = [ cfg.stateDir ];
  };
}
