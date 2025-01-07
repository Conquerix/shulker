{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.modules.pocket-id;
in
{
  options.shulker.modules.pocket-id = {
    enable = mkEnableOption "Enable pocket-id service";
    baseUrl = mkOption {
      type = types.str;
      default = "example.com";
      description = "Default url where pocket-id will be accessible.";
    };
    subDomain = mkOption {
      type = types.str;
      default = "pocket-id";
      description = "Default subdomain where pocket-id will be accessible.";
    };
    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/pocket-id";
      description = "State Directory.";
    };
    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Default internal port to open pocket-id.";
    };
  };

  config = mkIf cfg.enable {

    services.nginx = {
      enable = true;
      virtualHosts."pocket-id" = {
        serverName = "${cfg.subDomain}.${cfg.baseUrl}";
        forceSSL = true;
        useACMEHost = cfg.baseUrl;
        locations."/" = {
          #proxyWebsockets = true;
          proxyPass = "http://127.0.0.1:${toString cfg.port}";
          extraConfig = ''
            proxy_busy_buffers_size   512k;
            proxy_buffers   4 512k;
            proxy_buffer_size   256k;
          '';
        };
      };
    };

    users.users."pocket-id" = {
      uid = 2001;
      isSystemUser = true;
      createHome = false;
      group = "pocket-id";
    };

    users.groups."pocket-id" = {
      gid = 2001;
    };


    virtualisation.oci-containers.containers."pocket-id" = {
      image = "stonith404/pocket-id:latest";
      ports = [ "127.0.0.1:${toString cfg.port}:80" ];
      volumes = [ "${cfg.stateDir}:/app/backed/data" ];
      environmentFiles = [ config.opnix.secrets.pocket-id-env.path ];
      environment = {
        PUBLIC_APP_URL = "https://${cfg.subDomain}.${cfg.baseUrl}";
        TRUST_PROXY = "true";
        PUID = "${toString config.users.users."pocket-id".uid}";
        PGID = "${toString config.users.groups."pocket-id".gid}";
      };
    };

    environment.persistence = mkIf (config.shulker.modules.impermanence.enable) {
      "/nix/persist".directories = [ 
        {
          directory = cfg.stateDir;
          mode = "u=rwx,g=rx,o=";
          user = "pocket-id";
          group = "pocket-id";
        }
      ];
    };

    opnix.secrets.pocket-id-env = {
      source = "MAXMIND_LICENSE_KEY={{ op://Shulker/${config.networking.hostName}/Pocket-ID Maxmind License Key }}";
    };
  };
}
