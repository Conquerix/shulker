{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.modules.prowlarr;
in
{
  options.shulker.modules.prowlarr = {
    enable = mkEnableOption "Enable prowlarr service";
    baseUrl = mkOption {
      type = types.str;
      default = "example.com";
      description = "Default url where prowlarr will be accessible.";
    };
    subDomain = mkOption {
      type = types.str;
      default = "prowlarr";
      description = "Default subdomain where prowlarr will be accessible.";
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
      virtualHosts."prowlarr" = {
        serverName = "${cfg.subDomain}.${cfg.baseUrl}";
        forceSSL = true;
        useACMEHost = cfg.baseUrl;
        listenAddresses = cfg.listenAddresses;
        locations."/" = {
          proxyWebsockets = true;
          proxyPass = "http://127.0.0.1:9696";
          extraConfig = ''
            proxy_busy_buffers_size   512k;
            proxy_buffers   4 512k;
            proxy_buffer_size   256k;
          '';
        };
      };
    };

    services.prowlarr.enable = true;

    environment.persistence = mkIf (config.shulker.modules.impermanence.enable) {
      "/nix/persist".directories = [
        {
          directory = "/var/lib/private/prowlarr";
          mode = "u=rwx,g=,o=";
        }
      ];
    };
  };
}
