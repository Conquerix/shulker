{
  config,
  lib,
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

    services.beszel.hub = {
      enable = true;
      port = cfg.port;
      dataDir = cfg.stateDir;
      environmentFile = config.services.onepassword-secrets.secrets.beszelHubEnv.path;
      environment = {
        APP_URL = cfg.appUrl;
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
    # services.borgmatic.settings.sqlite_databases = [
    #   {
    #     name = "beszel-hub-db";
    #     path = "${cfg.stateDir}/data/database/database.sqlite";
    #   }
    # ];
  };
}
