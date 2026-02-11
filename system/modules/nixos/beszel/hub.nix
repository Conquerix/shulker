{
  config,
  lib,
  pkgs,
  ...
}:

with lib;
let
  cfg = config.shulker.system.modules.beszel.hub;
in
{
  options.shulker.system.modules.beszel.hub = {
    enable = mkEnableOption "Enable beszel hub service.";
    impermanence = mkEnableOption "Enable impermanence.";
    appUrl = mkOption {
      type = types.str;
      default = "example.com";
      description = "Url where beszel hub will be accessible.";
    };
    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/beszel/hub";
      description = "State Directory.";
    };
    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Default internal port to open beszel hub.";
    };
  };

  config = mkIf cfg.enable {

    users.groups.beszel-hub = { };
    users.users.beszel-hub = {
      isSystemUser = true;
      group = "beszel-hub";
    };

    systemd.services.beszel-hub = {
      description = "Beszel Server Monitoring Web App";

      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      environment = {
        APP_URL = cfg.appUrl;
        USER_EMAIL = "conquerix@shulker.link";
        USER_PASSWORD = "changeme!";
      };

      serviceConfig = {
        ExecStart = ''
          ${pkgs.beszel}/bin/beszel-hub serve --http='127.0.0.1:${toString cfg.port}'
        '';

        WorkingDirectory = cfg.stateDir;
        User = "beszel-hub";
        Restart = "always";
        RestartSec = "3s";
      };
    };

    environment.persistence = mkIf cfg.impermanence {
      "/nix/persist".directories = [
        {
          directory = "${cfg.stateDir}";
          mode = "u=rwx,g=rx,o=rx";
          user = "beszel-hub";
          group = "beszel-hub";
        }
      ];
    };

    shulker.system.modules.backup.dirs = [ cfg.stateDir ];
    services.borgmatic.settings.sqlite_databases = [
      {
        name = "beszel-hub-db";
        path = "${cfg.stateDir}/beszel-data/data.db";
      }
      {
        name = "beszel-hub-aux-db";
        path = "${cfg.stateDir}/beszel-data/auxiliary.db";
      }
    ];
  };
}
