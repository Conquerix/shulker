{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.modules.sonarr;
in
{
  options.shulker.modules.sonarr = {
    enable = mkEnableOption "Enable sonarr service";
    baseUrl = mkOption {
      type = types.str;
      default = "example.com";
      description = "Default url where sonarr will be accessible.";
    };
    subDomain = mkOption {
      type = types.str;
      default = "sonarr";
      description = "Default subdomain where sonarr will be accessible.";
    };
    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/sonarr";
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
      virtualHosts."sonarr" = {
        serverName = "${cfg.subDomain}.${cfg.baseUrl}";
        forceSSL = true;
        useACMEHost = cfg.baseUrl;
        listenAddresses = cfg.listenAddresses;
        locations."/" = {
          proxyWebsockets = true;
          proxyPass = "http://127.0.0.1:8989";
          extraConfig = ''
            proxy_busy_buffers_size   512k;
            proxy_buffers   4 512k;
            proxy_buffer_size   256k;
          '';
        };
      };
    };

    services.sonarr = {
      enable = true;
      dataDir = cfg.stateDir;
      group = "vod";
    };

    environment.persistence = mkIf (config.shulker.modules.impermanence.enable) {
      "/nix/persist".directories = [
        {
          directory = "/var/lib/sonarr";
          mode = "u=rwx,g=rx,o=";
          user = config.services.sonarr.user;
          group = config.services.sonarr.group;
        }
      ];
    };
  };
}
