{
  config,
  lib,
  pkgs,
  ...
}:

with lib;
let
  cfg = config.shulker.system.modules.karakeep;
in
{
  options.shulker.system.modules.karakeep = {
    enable = mkEnableOption "Enable karakeep service";
    baseUrl = mkOption {
      type = types.str;
      default = "example.com";
      description = "Default url where karakeep will be accessible.";
    };
    subDomain = mkOption {
      type = types.str;
      default = "karakeep";
      description = "Default subdomain where karakeep will be accessible.";
    };
    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Default internal port to open karakeep.";
    };
  };

  config = mkIf cfg.enable {

    services.nginx = {
      enable = true;
      virtualHosts."karakeep" = {
        serverName = "${cfg.subDomain}.${cfg.baseUrl}";
        forceSSL = true;
        useACMEHost = cfg.baseUrl;
        locations."/" = {
          #proxyWebsockets = true;
          proxyPass = "http://127.0.0.1:${toString cfg.port}";
          extraConfig = ''
            proxy_busy_buffers_size   512k;
            proxy_buffers   4 512k;
            proxy_buffer_size   256k;
          '';
        };
      };
    };
    services.meilisearch.package = pkgs.meilisearch;
    services.karakeep = {
      enable = true;
      environmentFile = config.services.onepassword-secrets.secrets.karakeepEnv.path;
      extraEnvironment = {
        NEXTAUTH_URL = "https://${cfg.subDomain}.${cfg.baseUrl}";
        PORT = toString cfg.port;
        DISABLE_SIGNUPS = "true";
        DISABLE_NEW_RELEASE_CHECK = "true";
        DISABLE_PASSWORD_AUTH = "true";
      };
    };

    environment.persistence = mkIf (config.shulker.system.modules.impermanence.enable) {
      "/nix/persist".directories = [
        {
          directory = "/var/lib/karakeep";
          mode = "u=rwx,g=rx,o=";
          user = "karakeep";
          group = "karakeep";
        }
      ];
    };

    services.onepassword-secrets.secrets.karakeepEnv = {
      reference = "op://Shulker/${config.networking.hostName}/Karakeep env";
      services = [ "karakeep-workers" "karakeep-web" ];
    };
  };
}
