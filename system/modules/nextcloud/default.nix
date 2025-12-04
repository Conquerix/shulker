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
      secretFile = config.services.onepassword-secrets.secrets.nextcloudSecretFile.path;
      settings = {
        trusted_proxies = [ "localhost" "127.0.0.1" ];
        trusted_domains = [ "${cfg.subDomain}.${cfg.baseUrl}" ];
      };
      database.createLocally = true;
      config = {
        dbtype = "pgsql";
        adminpassFile = config.services.onepassword-secrets.secrets.nextcloudAdminPassFile.path;
      };
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

    services.onepassword-secrets.secrets.nextcloudSecretFile = {
      reference = "op://Shulker/${config.networking.hostName}/Nextcloud secret";
      services = [ "docker" ];
      mode = "0750";
      owner = "nextcloud";
      group = "nextcloud";
    };

    services.onepassword-secrets.secrets.nextcloudDbSecretFile = {
      reference = "op://Shulker/${config.networking.hostName}/Nextcloud db secret";
      services = [ "docker" ];
      mode = "0750";
      owner = "nextcloud";
      group = "nextcloud";
    };

    services.onepassword-secrets.secrets.nextcloudAdminPassFile = {
      reference = "op://Shulker/${config.networking.hostName}/Nextcloud admin pass";
      services = [ "docker" ];
      mode = "0750";
      owner = "nextcloud";
      group = "nextcloud";
    };
  };
}
