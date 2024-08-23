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
    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Default internal port to open transmission.";
    };
    address = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Default address to which transimission will listen.";
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
      };
    };


    services.nginx = {
      enable = true;
      virtualHosts."searx" = {
        serverName = "${cfg.subDomain}.${cfg.baseUrl}";
        forceSSL = true;
        useACMEHost = cfg.baseUrl;
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString cfg.port}";
        };
      };
    };
  };
}
