{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.modules.authentik;
in
{
  options.shulker.modules.authentik = {
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
    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Default internal port to open authentik.";
    };
    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/authentik";
      description = "State Directory.";
    };
  };

  config = mkIf cfg.enable {

    networking.firewall = {
      enable = true;
      allowedTCPPorts = [ 80 443 ];
    };

    services.authentik = {
      enable = true;
      # The environmentFile needs to be on the target host!
      # Best use something like sops-nix or agenix to manage it
      environmentFile = "/run/secrets/authentik/authentik-env";
      settings = {
        listen.port = cfg.port;
        disable_startup_analytics = true;
        avatars = "initials";
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
          proxyPass = "http://127.0.0.1:${toString cfg.port}";
        };
      };
    };

    opsm.secrets = {
      authentik-env-file.secretRef = "op://Shulker/${config.networking.hostName}/Authentik Environment File";
    };
  };
}
