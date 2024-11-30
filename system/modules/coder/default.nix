{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.modules.coder;
in
{
  options.shulker.modules.coder = {
    enable = mkEnableOption "Enable coder service";
    baseUrl = mkOption {
      type = types.str;
      default = "example.com";
      description = "Default url where coder will be accessible.";
    };
    subDomain = mkOption {
      type = types.str;
      default = "coder";
      description = "Default subdomain where coder will be accessible.";
    };
    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/coder";
      description = "State Directory.";
    };
    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Default internal port to open coder.";
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
      virtualHosts."coder" = {
        serverName = "${cfg.subDomain}.${cfg.baseUrl}";
        forceSSL = true;
        useACMEHost = cfg.baseUrl;
        locations."/" = {
          proxyWebsockets = true;
          proxyPass = "http://127.0.0.1:${toString cfg.port}";
        };
      };
    };

    services.coder = {
      enable = true;
      listenAddress = "127.0.0.1:${toString cfg.port}";
      homeDir = cfg.stateDir;
      accessUrl = "https://${cfg.subDomain}.${cfg.baseUrl}";
      wildcardAccessUrl = "*.${cfg.subDomain}.${cfg.baseUrl}";
      environment.file = config.opnix.secrets.coder-env.path;
    };

    environment.persistence = mkIf (config.shulker.modules.impermanence.enable) {
      "/nix/persist".directories = [ 
        {
          directory = cfg.stateDir;
          mode = "u=rwx,g=rx,o=";
        }
      ];
    };

    users.users.coder.extraGroups = [ "docker" ];

    opnix.secrets.coder-env = {
      source = ''
        CODER_OIDC_ISSUER_URL="${cfg.oidcIssuer}"
        CODER_OIDC_EMAIL_DOMAIN="shulker.link"
        CODER_OIDC_CLIENT_ID="${cfg.oidcClientID}"
        CODER_OIDC_CLIENT_SECRET="{{ op://Shulker/${config.networking.hostName}/Coder OIDC Client Secret }}"
        CODER_DISABLE_PASSWORD_AUTH=true
      '';
    };

    opnix.systemdWantedBy = [ "coder" ];
  };
}
