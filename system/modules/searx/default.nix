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
    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Default internal port to open searx.";
    };
  };

  config = mkIf cfg.enable {

    virtualisation.oci-containers.containers = {
      searxng = {
        image = "searxng/searxng:latest";
        ports = [ "${toString cfg.port}:8080" ];
        environment = {
          INSTANCE_NAME = "Shulker search";
          SEARXNG_BASE_URL = "https://${cfg.subDomain}.${cfg.baseUrl}/";
        };
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
