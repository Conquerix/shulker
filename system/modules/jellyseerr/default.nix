{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.modules.jellyseerr;
in
{
  options.shulker.modules.jellyseerr = {
    enable = mkEnableOption "Enable jellyseerr service";
    baseUrl = mkOption {
      type = types.str;
      default = "example.com";
      description = "Default url where jellyseerr will be accessible.";
    };
    subDomain = mkOption {
      type = types.str;
      default = "jellyseerr";
      description = "Default subdomain where jellyseerr will be accessible.";
    };
    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Default internal port to open jellyseerr.";
    };
    listenAddresses = mkOption {
      type = types.listOf types.str;
      default = [ "0.0.0.0" ];
      description = "Addresses that the nginx virtual host will listen to. (Useful for only opening access internally)";
    };
  };

  config = mkIf cfg.enable {

    services.nginx = {
      enable = true;
      virtualHosts."jellyseerr" = {
        serverName = "${cfg.subDomain}.${cfg.baseUrl}";
        forceSSL = true;
        useACMEHost = cfg.baseUrl;
        listenAddresses = cfg.listenAddresses;
        locations."/" = {
          proxyWebsockets = true;
          proxyPass = "http://127.0.0.1:${toString cfg.port}";
          extraConfig = ''
            proxy_busy_buffers_size   512k;
            proxy_buffers   4 512k;
            proxy_buffer_size   256k;
          '';
        };
      };
    };

    services.jellyseerr = {
      enable = true;
      port = cfg.port;
    };

    environment.persistence = mkIf (config.shulker.modules.impermanence.enable) {
      "/nix/persist".directories = [ 
        {
          directory = "/var/lib/jellyseerr";
          mode = "u=rwx,g=rx,o=";
        }
      ];
    };
  };
}
