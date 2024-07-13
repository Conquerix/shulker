{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.modules.authelia;
in
{
  options.shulker.modules.authelia = {
    enable = mkEnableOption "Enable authelia service.";
    baseUrl = mkOption {
      type = types.str;
      default = "example.com";
      description = "Default url where authelia will be accessible.";
    };
    subDomain = mkOption {
      type = types.str;
      default = "authelia";
      description = "Default subdomain where authelia will be accessible.";
    };
    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Default internal port to open authelia.";
    };
    bindAddresses = mkOption {
      type = types.listOf types.str;
      default = [ "0.0.0.0" ];
      description = "IP addresses to listen to for the nginx hosts.";
    };
    instanceName = mkOption {
      type = types.str;
      default = "shulker";
      description = "Default intance name to use.";
    };
    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/authelia";
      description = "Default path to store authelia data.";
    };
  };

  config = mkIf cfg.enable {

    networking.firewall = {
      enable = true;
      allowedTCPPorts = [ 80 443 ];
    };

    services.nginx = {
      enable = true;
      virtualHosts = {
        "authelia" = {
          serverName = "${cfg.subDomain}.${cfg.baseUrl}";
          forceSSL = true;
          useACMEHost = cfg.baseUrl;
          listenAddresses = cfg.bindAddresses;
          locations."/" = {
            proxyPass = "http://127.0.0.1:${toString cfg.port}";
          };
        };
      };
    };

    services.authelia.instances."${cfg.instanceName}" = {
      enable = true;
      settings = {
        server = {
          host = "127.0.0.1";
          port = cfg.port;
        };
        theme = "dark";
        log.file_path = "${cfg.stateDir}/config/authelia.log";
        access_control.default_policy = "one_factor";
        default_redirection_url = "https://${cfg.subDomain}.${cfg.baseUrl}";
        authentication_backend.file.path = "${cfg.stateDir}/config/users_database.yml";
        storage.local.path = "${cfg.stateDir}/config/db.sqlite3";
        session.domain = cfg.baseUrl;
        notifier.filesystem.filename = "${cfg.stateDir}/config/notifications.txt";
      };
      secrets = {
        jwtSecretFile = "/secrets/authelia-jwt-secret";
        storageEncryptionKeyFile = "/secrets/authelia-storage-encryption-key";
      };
    };

    opsm.secrets = {
      authelia-jwt-secret = {
        secretRef = "op://Shulker/${config.networking.hostName}/Authelia JWT Secret";
        user = "authelia-${cfg.instanceName}";
        mode = "0500";
      };
      authelia-storage-encryption-key = {
        secretRef = "op://Shulker/${config.networking.hostName}/Authelia Storage Encryption Key";
        user = "authelia-${cfg.instanceName}";
        mode = "0500";
      };
    };
  };
}
