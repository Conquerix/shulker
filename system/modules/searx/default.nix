{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.modules.searx;
in
{
  options.shulker.modules.searx = {
    enable = mkEnableOption "Enable searx service";
    baseUrl = mkOption {
      type = types.str;
      default = "example.com";
      description = "Default url where searx will be accessible.";
    };
    subDomain = mkOption {
      type = types.str;
      default = "searx";
      description = "Default subdomain where searx will be accessible.";
    };
    listenAddresses = mkOption {
      type = types.listOf types.str;
      default = [ "0.0.0.0" ];
      description = "Addresses that the nginx virtual host will listen to. (Useful for only opening access internally)";
    };
    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Default internal port to open searx.";
    };
  };

  config = mkIf cfg.enable {

    services.searx = {
      enable = true;
      environmentFile = config.opnix.secrets.searx-env.path;
      settings = {
        server.port = cfg.port;
        server.secret_key = "@SEARX_SECRET_KEY@";
        server.base_url = "https://${cfg.subDomain}.${cfg.baseUrl}/";
      };
    };

    services.nginx = {
      enable = true;
      virtualHosts."searx" = {
        serverName = "${cfg.subDomain}.${cfg.baseUrl}";
        forceSSL = true;
        useACMEHost = cfg.baseUrl;
        listenAddresses = cfg.listenAddresses;
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString cfg.port}";
        };
      };
    };

    opnix.secrets.searx-env = {
      source = ''
        SEARX_SECRET_KEY="{{ op://Shulker/${config.networking.hostName}/Searx Secret Key }}"
      '';
    };

    opnix.systemdWantedBy = [ "searx-init" ];
  };
}
