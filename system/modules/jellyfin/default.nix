{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.modules.jellyfin;
in
{
  options.shulker.modules.jellyfin = {
    enable = mkEnableOption "Enable jellyfin service";
    baseUrl = mkOption {
      type = types.str;
      default = "example.com";
      description = "Default url where jellyfin will be accessible.";
    };
    subDomain = mkOption {
      type = types.str;
      default = "jellyfin";
      description = "Default subdomain where jellyfin will be accessible.";
    };
    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/jellyfin";
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
      virtualHosts."jellyfin" = {
        serverName = "${cfg.subDomain}.${cfg.baseUrl}";
        forceSSL = true;
        useACMEHost = cfg.baseUrl;
        listenAddresses = cfg.listenAddresses;
        locations."/" = {
          proxyWebsockets = true;
          proxyPass = "http://127.0.0.1:8096";
          extraConfig = ''
            proxy_busy_buffers_size   512k;
            proxy_buffers   4 512k;
            proxy_buffer_size   256k;
          '';
        };
      };
    };

    services.jellyfin = {
      enable = true;
      dataDir = cfg.stateDir;
      cacheDir = "${cfg.stateDir}/cache";
    };

    environment.persistence = mkIf (config.shulker.modules.impermanence.enable) {
      "/nix/persist".directories = [ 
        {
          directory = cfg.stateDir;
          mode = "u=rwx,g=rx,o=";
        }
      ];
    };
  };
}
