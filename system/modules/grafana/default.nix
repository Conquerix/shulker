{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.modules.grafana;
in
{
  options.shulker.modules.grafana = {
    enable = mkEnableOption "Enable grafana service";
    persistence = mkEnableOption "Enable grafana persistence in /nix/persist";
    baseUrl = mkOption {
      type = types.str;
      default = "example.com";
      description = "Default url where grafana will be accessible.";
    };
    subDomain = mkOption {
      type = types.str;
      default = "grafana";
      description = "Default subdomain where grafana will be accessible.";
    };
    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/grafana";
      description = "State Directory.";
    };
    listenAddresses = mkOption {
      type = types.listOf types.str;
      default = [ "0.0.0.0" ];
      description = "Addresses that the nginx virtual host will listen to. (Useful for only opening access internally)";
    };
    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Default internal port to open grafana.";
    };
    oidcIssuer = mkOption {
      type = types.str;
      example = "https://openid.example.com";
      description = "URL to OpenID issuer.";
    };
    oidcClientID = mkOption {
      type = types.str;
      description = "OpenID Connect client ID.";
    };
  };

  config = mkIf cfg.enable {

    services.nginx = {
      enable = true;
      virtualHosts."grafana" = {
        serverName = "${cfg.subDomain}.${cfg.baseUrl}";
        forceSSL = true;
        useACMEHost = cfg.baseUrl;
        listenAddresses = cfg.listenAddresses;
        locations."/" = {
          proxyWebsockets = true;
          proxyPass = "http://127.0.0.1:${toString cfg.port}";
        };
      };
    };

    services.grafana = {
      enable = true;
      dataDir = cfg.stateDir;
      settings = {
        
      };
    };

    environment.persistence = mkIf (config.shulker.modules.impermanence.enable && cfg.persistence) {
      "/nix/persist".directories = [ 
        {
          directory = cfg.stateDir;
          mode = "u=rwx,g=rx,o=";
        }
      ];
    };

    systemd.services.grafana.serviceConfig.EnvironmentFile = opnix.secrets.grafana-env.path;

    opnix.secrets.grafana-env = {
      source = ''
        grafana_OIDC_ISSUER_URL="${cfg.oidcIssuer}"
        grafana_OIDC_EMAIL_DOMAIN="shulker.link"
        grafana_OIDC_CLIENT_ID="${cfg.oidcClientID}"
        grafana_OIDC_CLIENT_SECRET="{{ op://Shulker/${config.networking.hostName}/grafana OIDC Client Secret }}"
        grafana_DISABLE_PASSWORD_AUTH=true
      '';
    };

    opnix.systemdWantedBy = [ "grafana" ];
  };
}