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
        dns = {
          base_domain = "internal.${cfg.baseUrl}";
        };
        noise.private_key_path = "${cfg.stateDir}/noise_private.key";
        derp.server.private_key_path = "${cfg.stateDir}/derp_server_private.key";
        database.sqlite.path = "${cfg.stateDir}/db.sqlite";
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
        extraConfig = ''
          proxy_http_version 1.1;
          proxy_set_header Upgrade $http_upgrade;
          proxy_set_header Connection $connection_upgrade;
          proxy_set_header Host $server_name;
          proxy_buffering off;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
          add_header Strict-Transport-Security "max-age=15552000; includeSubDomains" always;
        '';
      };
    };

    environment.persistence = mkIf (config.shulker.modules.impermanence.enable) {
      "/nix/persist".directories = [ 
        {
          directory = cfg.stateDir;
          user = "headscale";
          group = "headscale";
          mode = "u=rwx,g=rx,o=";
        }
      ];
    };

    opnix.secrets.headscale-oidc-client-secret = {
      source = "{{ op://Shulker/${config.networking.hostName}/Headscale OIDC Client Secret }}";
      user = "headscale";
      group = "headscale";
    };

    opnix.systemdWantedBy = [ "headscale" ];
  };
}