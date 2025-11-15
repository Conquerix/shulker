{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.system.modules.donetick;
in
{
  options.shulker.system.modules.donetick = {
    enable = mkEnableOption "Enable donetick service.";
    impermanence = mkEnableOption "Enable impermanence.";
    baseUrl = mkOption {
      type = types.str;
      default = "example.com";
      description = "Default url where donetick will be accessible.";
    };
    subDomain = mkOption {
      type = types.str;
      default = "donetick";
      description = "Default subdomain where donetick will be accessible.";
    };
    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/donetick";
      description = "State Directory.";
    };
    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Default internal port to open donetick.";
    };
  };

  config = mkIf cfg.enable {

    # Containers
    virtualisation.oci-containers.containers."donetick" = {
      image = "donetick/donetick";
      environmentFiles = [ config.services.onepassword-secrets.secrets.donetickEnv.path ];
      environment = {
        "DT_NAME" = "Shulker ToDo";
        "DT_ENV" = "selfhosted";
        "DT_DATABASE_TYPE" = "sqlite";
        "DT_SQLITE_PATH" = "/donetick-data/donetick.db";
        "DT_IS_USER_CREATION_DISABLED" = "true";
        "DT_IS_DONE_TICK_DOT_COM" = "false";
        "DT_OAUTH2_REDIRECT_URL" = "https://${cfg.subDomain}.${cfg.baseUrl}/auth/oauth2";


      };
      ports = [ "127.0.0.1:${toString cfg.port}:2021" ];
      volumes = [
        "${cfg.stateDir}/data:/donetick-data"
        "${cfg.stateDir}/config:/config"
      ];
    };

    services.nginx = {
      enable = true;
      virtualHosts."donetick" = {
        serverName = "${cfg.subDomain}.${cfg.baseUrl}";
        forceSSL = true;
        useACMEHost = cfg.baseUrl;
        locations."/" = {
          proxyWebsockets = true;
          proxyPass = "http://127.0.0.1:${toString cfg.port}";
        };
      };
    };

    environment.persistence = mkIf (cfg.impermanence) {
      "/nix/persist".directories = [ 
        {
          directory = cfg.stateDir;
          mode = "u=rwx,g=,o=";
          user = "donetick";
          group = "donetick";
        }
      ];
    };

    services.onepassword-secrets.secrets.donetickEnv = {
      reference = "op://Shulker/${config.networking.hostName}/Donetick env";
      services = [ "docker" ];
    };
  };
}
