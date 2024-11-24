{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.modules.headscale;
in
{
  options.shulker.modules.headscale = {
    enable = mkEnableOption "Enable headscale service";
    baseUrl = mkOption {
      type = types.str;
      example = "example.com";
      description = "Default url where headscale will be accessible.";
    };
    subDomain = mkOption {
      type = types.str;
      default = "headscale";
      description = "Default subdomain where headscale will be accessible.";
    };
    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Default internal port to open headscale.";
    };
    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/headscale";
      description = "State Directory.";
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

    services.headscale = {
      enable = true;
      port = cfg.port;
      settings = {
        server_url = "https://${cfg.subDomain}.${cfg.baseUrl}:443";
        oidc = {
          issuer = cfg.oidcIssuer;
          client_id = cfg.oidcClientID;
          client_secret_path = config.opnix.secrets.headscale-oidc-client-secret.path;
        };
      };
    };

    services.nginx = {
      enable = true;
      virtualHosts."headscale" = {
        serverName = "${cfg.subDomain}.${cfg.baseUrl}";
        forceSSL = true;
        useACMEHost = cfg.baseUrl;
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString cfg.port}";
        };
      };
    };

    opnix.secrets.headscale-oidc-client-secret = {
      source = "{{ op://Shulker/${config.networking.hostName}/Headscale OIDC Client Secret }}";
      user = "headscale";
      group = "headscale";
    };
  };
}
