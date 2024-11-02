{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.modules.stalwart;
in
{
  options.shulker.modules.stalwart = {
    enable = mkEnableOption "Enable stalwart service.";
    baseUrl = mkOption {
      type = types.str;
      default = "example.com";
      description = "Default url where stalwart will be accessible.";
    };
    subDomain = mkOption {
      type = types.str;
      default = "stalwart";
      description = "Default subdomain where stalwart will be accessible.";
    };
    port = mkOption {
      type = types.port;
      default = 3000;
      description = "Default internal port to open stalwart.";
    };
    address = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Default address to which stalwart will listen.";
    };
  };

  config = mkIf cfg.enable {

    #opsm.secrets.bookstack-client-secret-key = {
    #  secretRef = "op://Shulker/${config.networking.hostName}/Bookstack Client Secret Key";
    #  user = config.services.bookstack.user;
    #  group = config.services.bookstack.group;
    #};

    #opsm.secrets.bookstack-app-secret = {
    #  secretRef = "op://Shulker/${config.networking.hostName}/Bookstack App Secret";
    #  user = config.services.bookstack.user;
    #  group = config.services.bookstack.group;
    #};

    services.stalwart-mail = {
      enable = true;
      package = pkgs.stalwart-mail;
      openFirewall = true;
      settings = {
        certificate = {
          "shulker.fr" = {
            cert = "%{file:/var/lib/acme/shulker.fr/fullchain.pem}%";
            private-key = "%{file:/var/lib/acme/shulker.fr/key.pem}%";
          };
          "the-inbetween.net" = {
            cert = "%{file:/var/lib/acme/the-inbetween.net/fullchain.pem}%";
            private-key = "%{file:/var/lib/acme/the-inbetween.net/key.pem}%";
          };
        };
      };
    };

    services.nginx = {
      enable = true;
      virtualHosts."stalwart" = {
        serverName = "${cfg.subDomain}.${cfg.baseUrl}";
        forceSSL = true;
        useACMEHost = cfg.baseUrl;
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString cfg.httpPort}";
        };
      };
    };

    environment.persistence = mkIf (config.shulker.modules.impermanence.enable) {
      "/nix/persist".directories = [ 
        {
          directory = "/var/lib/stalwart-mail";
          user = "stalwart-mail";
          group = "stalwart-mail";
          mode = "u=rwx,g=rx,o=";
        }
      ];
    };
  };
}
