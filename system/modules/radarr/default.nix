{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.modules.radarr;
in
{
  options.shulker.modules.radarr = {
    enable = mkEnableOption "Enable radarr service";
    baseUrl = mkOption {
      type = types.str;
      default = "example.com";
      description = "Default url where radarr will be accessible.";
    };
    subDomain = mkOption {
      type = types.str;
      default = "radarr";
      description = "Default subdomain where radarr will be accessible.";
    };
    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/radarr";
      description = "State Directory.";
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
      virtualHosts."radarr" = {
        serverName = "${cfg.subDomain}.${cfg.baseUrl}";
        forceSSL = true;
        useACMEHost = cfg.baseUrl;
        listenAddresses = cfg.listenAddresses;
        locations."/" = {
          proxyWebsockets = true;
          proxyPass = "http://127.0.0.1:7878";
          extraConfig = ''
            proxy_busy_buffers_size   512k;
            proxy_buffers   4 512k;
            proxy_buffer_size   256k;
          '';
        };
      };
    };

    services.radarr = {
      enable = true;
      dataDir = cfg.stateDir;
      group = "vod";
    };

    environment.persistence = mkIf (config.shulker.modules.impermanence.enable) {
      "/nix/persist".directories = [
        {
          directory = "/var/lib/radarr";
          mode = "u=rwx,g=rx,o=";
          user = config.services.radarr.user;
          group = config.services.radarr.group;
        }
      ];
    };
  };
}
