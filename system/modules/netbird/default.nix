{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.modules.netbird;
in
{
  options.shulker.modules.netbird = {
    enable = mkEnableOption "Enable zitadel service.";
    baseUrl = mkOption {
      type = types.str;
      default = "example.com";
      description = "Default url where zitadel  will be accessible.";
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
    dbPort = mkOption {
      type = types.port;
      default = 5432;
      description = "Default internal port to open postgresql.";
    };
    bindAddresses = mkOption {
      type = types.listOf types.str;
      default = [ "0.0.0.0" ];
      description = "IP addresses to listen to for the nginx hosts.";
    };
    dbDataDir = mkOption {
      type = types.str;
      default = "/var/lib/zitadel/db";
      description = "Default path to store zitadel db data.";
    };
  };

  config = mkIf cfg.enable {

  	networking.firewall = {
  	  enable = true;
  	  allowedTCPPorts = [ 80 443 ];
  	};

    virtualisation.oci-containers.containers = {
      zitadel = {
        image = "ghcr.io/zitadel/zitadel:stable";
        extraOptions = ["--network=host"];
        #entrypoint = "ls -la /"; #while read line; do echo $line; done < /etc/passwd";
        cmd = [
          "start" #-from-init"
          "--config" "/example-zitadel-config.yaml"
          "--config" "/example-zitadel-secrets.yaml"
          #"--steps" "/example-zitadel-init-steps.yaml"
          "--masterkeyFile" "/masterkey"
          "--tlsMode" "external"
        ];
        volumes = [
          "${zitadel-config}:/example-zitadel-config.yaml:ro"
          "/secrets/zitadel-secrets:/example-zitadel-secrets.yaml:ro"
          "${zitadel-init-steps}:/example-zitadel-init-steps.yaml:ro"
          "/secrets/zitadel-master-key:/masterkey:ro"
        ];
      };
      zitadel-db = {
        image = "postgres:16-alpine";
        environmentFiles = [ "/secrets/zitadel-db-creds" ];
        ports = [ "127.0.0.1:${toString cfg.dbPort}:5432" ];
        volumes = [
          "${cfg.dbDataDir}:/var/lib/postgresql/data:rw"
        ];
      };
    };

    services.nginx = {
      enable = true;
      virtualHosts = {
        "zitadel" = {
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

    opsm.secrets = {
      zitadel-master-key = {
        secretRef = "op://Shulker/${config.networking.hostName}/Zitadel Master Key";
        user = "conquerix";
        mode = "0400";
      };
      zitadel-secrets = {
        secretRef = "op://Shulker/${config.networking.hostName}/zitadel-secrets";
        user = "conquerix";
        mode = "0400";
      };
      zitadel-db-creds.secretRef = "op://Shulker/${config.networking.hostName}/zitadel-db-creds";
    };
  };
}
