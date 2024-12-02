{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.modules.transmission;
in
{
  options.shulker.modules.transmission = {
    enable = mkEnableOption "Enable transmission service";
    baseUrl = mkOption {
      type = types.str;
      default = "example.com";
      description = "Default url where transmission will be accessible.";
    };
    subDomain = mkOption {
      type = types.str;
      default = "searx";
      description = "Default subdomain where transmission will be accessible.";
    };
    listenAddresses = mkOption {
      type = types.listOf types.str;
      default = [ "0.0.0.0" ];
      description = "Addresses that the nginx virtual host will listen to. (Useful for only opening access internally)";
    };
    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Default internal port to open transmission.";
    };
    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/transmission";
      description = "State Directory.";
    };
  };

  config = mkIf cfg.enable {

    services.transmission = {
      enable = true;
      openFirewall = true;
      openRPCPort = true;
      settings = {
        download-dir = cfg.stateDir;
        incomplete-dir ="${cfg.stateDir}/.incomplete";
        rpc-port = cfg.port;
        rpc-host-whitelist = "${cfg.subDomain}.${cfg.baseUrl}";
      };
    };


    services.nginx = {
      enable = true;
      virtualHosts."transmission" = {
        serverName = "${cfg.subDomain}.${cfg.baseUrl}";
        forceSSL = true;
        useACMEHost = cfg.baseUrl;
        listenAddresses = cfg.listenAddresses;
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString cfg.port}";
        };
      };
    };
  };
}
