{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.modules.zitadel;
in
{
  options.shulker.modules.zitadel = {
    enable = mkEnableOption "Enable zitadel service (and cockroach too, because it needs a database).";
    baseUrl = mkOption {
      type = types.str;
      default = "example.com";
      description = "Default url where zitadel (and cockroachdb) will be accessible.";
    };
    subDomain = mkOption {
      type = types.str;
      default = "zitadel";
      description = "Default subdomain where zitadel will be accessible.";
    };
    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Default internal port to open zitadel.";
    };
    dbSubDomain = mkOption {
      type = types.str;
      default = "cockroachdb";
      description = "Default subdomain where cockroachdb will be accessible.";
    };
    dbPort = mkOption {
      type = types.port;
      default = 26257;
      description = "Default internal port to open cockroachDB.";
    };
    dbHttpPort = mkOption {
      type = types.port;
      default = 9090;
      description = "Default internal port to open cockroachDB adminUI.";
    };
  };

  config = mkIf cfg.enable {

  	networking.firewall = {
  	  enable = true;
  	  allowedTCPPorts = [ 80 443 ];
  	};

    services.zitadel = {
      #enable = true;
      settings = {
        Port = cfg.port;
        Database.cockroach = {
          Port = cfg.dbPort;
        };
        
      };
    };

    services.cockroachdb = {
      enable = true;
      listen.port = cfg.dbPort;
      http.port = cfg.dbHttpPort;
    };

    services.nginx = {
      enable = true;
      virtualHosts = {
        "zitadel" = {
          serverName = "${cfg.subDomain}.${cfg.baseUrl}";
          forceSSL = true;
          useACMEHost = cfg.baseUrl;
          locations."/" = {
            proxyPass = "http://127.0.0.1:${toString cfg.httpPort}";
          };
        };
        "cockroachdb" = {
          serverName = "${cfg.subDomain}.${cfg.baseUrl}";
          forceSSL = true;
          useACMEHost = cfg.baseUrl;
          locations."/" = {
            proxyPass = "http://127.0.0.1:${toString cfg.dbHttpPort}";
          };
        };
      };
    };
  };
}
