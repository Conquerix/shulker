{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.system.modules.nextcloud;
in
{
  options.shulker.system.modules.nextcloud = {
    enable = mkEnableOption "Enable nextcloud service.";
    impermanence = mkEnableOption "Enable impermanence.";
    baseUrl = mkOption {
      type = types.str;
      default = "example.com";
      description = "Default url where nextcloud will be accessible.";
    };
    subDomain = mkOption {
      type = types.str;
      default = "nextcloud";
      description = "Default subdomain where nextcloud will be accessible.";
    };
    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/nextcloud";
      description = "State Directory.";
    };
  };

  config = mkIf cfg.enable {

    services.nextcloud = {
      enable = true;
      package = pkgs.nextcloud32;
      #imaginary.enable = true;
      hostName = "nextcloud";
      https = true;
      home = cfg.stateDir;
      extraAppsEnable = false;
      appstoreEnable = true;
      settings = {
        trusted_proxies = [ "127.0.0.1/32" ];
        trusted_domains = [ "${cfg.subDomain}.${cfg.baseUrl}" ];
        log_type = "file";
      };
      database.createLocally = true;
      config = {
        dbtype = "pgsql";
        adminpassFile = config.services.onepassword-secrets.secrets.nextcloudAdminPassFile.path;
      };
    };

    services.nextcloud-whiteboard-server = {
      enable = true;
      settings.NEXTCLOUD_URL = "https://${cfg.subDomain}.${cfg.baseUrl}";
      secrets = [ config.services.onepassword-secrets.secrets.nextcloudWhiteboardSecret.path ];
    };

    services.nginx = {
      enable = true;
      virtualHosts."nextcloud" = {
        serverName = "${cfg.subDomain}.${cfg.baseUrl}";
        forceSSL = true;
        useACMEHost = cfg.baseUrl;
        #locations."/" = {
        #  proxyWebsockets = true;
        #  proxyPass = "http://127.0.0.1:${toString cfg.port}";
        #};
      };
      virtualHosts."nextcloud-whiteboard" = {
        serverName = "whiteboard-${cfg.subDomain}.${cfg.baseUrl}";
        forceSSL = true;
        useACMEHost = cfg.baseUrl;
        locations."/" = {
          proxyWebsockets = true;
          proxyPass = "http://127.0.0.1:3002"; # Can't customize the port :(
        };
      };
    };

    environment.persistence = mkIf (cfg.impermanence) {
      "/nix/persist".directories = [
        {
          directory = cfg.stateDir;
          mode = "u=rwx,g=rwx,o=";
          user = "nextcloud";
          group = "nextcloud";
        }
        {
          directory = config.services.postgresql.dataDir;
          mode = "u=rwx,g=rwx,o=";
          user = "postgres";
          group = "postgres";
        }
      ];
    };

    services.onepassword-secrets.secrets.nextcloudAdminPassFile = {
      reference = "op://Shulker/${config.networking.hostName}/Nextcloud admin pass";
      services = [ "nextcloud-setup" "nextcloud-update-db" ];
      mode = "0750";
      owner = "nextcloud";
      group = "nextcloud";
    };

    services.onepassword-secrets.secrets.nextcloudWhiteboardSecret = {
      reference = "op://Shulker/${config.networking.hostName}/Nextcloud whiteboard secret";
      services = [ "nextcloud-whiteboard-server" ];
      mode = "0750";
      owner = "nextcloud";
      group = "nextcloud";
    };
  };
}
