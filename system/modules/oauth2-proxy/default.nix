{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.modules.oauth2-proxy;
in
{
  options.shulker.modules.oauth2-proxy = {
    enable = mkEnableOption "Enable oauth2-proxy service";
    baseUrl = mkOption {
      type = types.str;
      default = "example.com";
      description = "Default url where oauth2-proxy will be accessible.";
    };
    subDomain = mkOption {
      type = types.str;
      default = "oauth2-proxy";
      description = "Default subdomain where oauth2-proxy will be accessible.";
    };
    listenAddresses = mkOption {
      type = types.listOf types.str;
      default = [ "0.0.0.0" ];
      description = "Addresses that the nginx virtual host will listen to. (Useful for only opening access internally)";
    };
    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Default internal port to open oauth2-proxy.";
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
    virtualHosts = mkOption {
      type =
        let
          vhostSubmodule = types.submodule {
            options = {
              allowed_groups = mkOption {
                type = types.nullOr (types.listOf types.str);
                description = "List of groups to allow access to this vhost, or null to allow all.";
                default = null;
              };
              allowed_emails = mkOption {
                type = types.nullOr (types.listOf types.str);
                description = "List of emails to allow access to this vhost, or null to allow all.";
                default = null;
              };
              allowed_email_domains = mkOption {
                type = types.nullOr (types.listOf types.str);
                description = "List of email domains to allow access to this vhost, or null to allow all.";
                default = null;
              };
            };
          };
          oldType = types.listOf types.str;
          convertFunc =
            x:
            warn
              "shulker.modules.oauth2-proxy.virtualHosts should be an attrset, found ${generators.toPretty { } x}"
              genAttrs
              x
              (_: { });
          newType = types.attrsOf vhostSubmodule;
        in
        types.coercedTo oldType convertFunc newType;
      default = { };
      example = {
        "protected.foo.com" = {
          allowed_groups = [ "admins" ];
          allowed_emails = [ "boss@foo.com" ];
        };
      };
      description = ''
        Nginx virtual hosts to put behind the oauth2 proxy.
        You can exclude specific locations by setting `auth_request off;` in the locations extraConfig setting.
      '';
    };
  };

  config = mkIf cfg.enable {

    services.nginx = {
      enable = true;
      virtualHosts."oauth2-proxy" = {
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

    services.oauth2-proxy = {
      enable = true;
      listenAddress = "127.0.0.1:${toString cfg.port}";
      provider = "oidc";
      clientID = cfg.oidcClientID;
      oidcIssuerUrl = cfg.oidcIssuer;
      httpAddress = "http://127.0.0.1:${toString cfg.port}";
      reverseProxy = true;
      redirectURL = "https://${cfg.subDomain}.${cfg.baseUrl}/oauth2/callback";
      nginx = {
        proxy = "https://${cfg.subDomain}.${cfg.baseUrl}/";
        domain = "${cfg.subDomain}.${cfg.baseUrl}";
        virtualHosts = cfg.virtualHosts;
      };
      keyFile = config.opnix.secrets.oauth2-proxy-env.path;
    };

    opnix.secrets.oauth2-proxy-env = {
      source = ''
        OAUTH2_PROXY_CLIENT_SECRET="{{ op://Shulker/${config.networking.hostName}/oauth2-proxy OIDC Client Secret }}"
      '';
    };

    opnix.systemdWantedBy = [ "oauth2-proxy" ];
  };
}
