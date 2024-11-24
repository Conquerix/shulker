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
      environmentFile = config.opnix.secrets.authentik-secret-key.path;
      settings = {
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
          proxyPass = "https://127.0.0.1:9443";
        };
      };
    };

    opnix.secrets.authentik-secret-key = {
      source = "AUTHENTIK_SECRET_KEY={{ op://Shulker/${config.networking.hostName}/Authentik Secret Key }}";
    };
  };
}
