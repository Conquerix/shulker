{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.system.modules.authentik;
in
{
  options.shulker.system.modules.authentik = {
    enable = mkEnableOption "Enable authentik service";
    baseUrl = mkOption {
      type = types.str;
      default = "example.com";
      description = "Default url where authentik will be accessible.";
    };
    subDomain = mkOption {
      type = types.str;
      default = "authentik";
      description = "Default subdomain where authentik will be accessible.";
    };
    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/authentik";
      description = "State Directory.";
    };
  };

  config = mkIf cfg.enable {

    services.authentik = {
      enable = true;
      # The environmentFile needs to be on the target host!
      # Best use something like sops-nix or agenix to manage it
      environmentFile = config.services.onepassword-secrets.secrets.authentikEnv.path;
      settings = {
        disable_startup_analytics = true;
        avatars = "initials";
        email = {
          host = "smtp.fastmail.com";
          port = 465;
          use_tls = true;
          use_ssl = false;
          from = "sso@beyondsmp.com";
        };
      };
    };

    services.nginx = {
      enable = true;
      virtualHosts."authentik" = {
        serverName = "${cfg.subDomain}.${cfg.baseUrl}";
        forceSSL = true;
        useACMEHost = cfg.baseUrl;
        locations."/" = {
          proxyWebsockets = true;
          proxyPass = "https://127.0.0.1:9443";
        };
      };
    };

    environment.persistence = mkIf (config.shulker.system.modules.impermanence.enable) {
      "/nix/persist".directories = [ 
        {
          directory = cfg.stateDir;
          mode = "u=rwx,g=rx,o=";
        }
        {
          directory = "/var/lib/private/authentik";
          mode = "u=rwx,g=rx,o=";
        }
        {
          directory = "/var/lib/redis-authentik";
          mode = "u=rwx,g=rx,o=";
        }
        {
          directory = "/var/lib/postgresql";
          mode = "u=rwx,g=rx,o=";
        }
      ];
    };

    services.onepassword-secrets.secrets.authentikEnv = {
      reference = "op://Shulker/${config.networking.hostName}/Authentik env";
      services = [ "authentik" "authentik-migrate" "authentik-worker" ];
    };
  };
}
