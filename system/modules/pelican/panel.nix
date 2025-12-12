{
  config,
  lib,
  pkgs,
  ...
}:

with lib;
let
  cfg = config.shulker.system.modules.pelican.panel;

  caddyFile = pkgs.writeText "Caddyfile" ''
    {
        admin off
        servers {
            trusted_proxies static 127.0.0.1 172.17.0.1 172.20.0.1
        }
    }

    :80 {
        root * /var/www/html/public
        encode gzip

        php_fastcgi 127.0.0.1:9000 {
        env PHP_VALUE "upload_max_filesize = 256M
                       post_max_size = 256M"
        }
        file_server
    }
  '';
in
{
  options.shulker.system.modules.pelican.panel = {
    enable = mkEnableOption "Enable pelican panel service.";
    impermanence = mkEnableOption "Enable impermanence.";
    baseUrl = mkOption {
      type = types.str;
      default = "example.com";
      description = "Default url where pelican panel will be accessible.";
    };
    subDomain = mkOption {
      type = types.str;
      default = "panel";
      description = "Default subdomain where pelican panel will be accessible.";
    };
    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/pelican/panel";
      description = "State Directory.";
    };
    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Default internal port to open pelican panel.";
    };
  };

  config = mkIf cfg.enable {

    users.groups.pelican-panel.gid = 82;
    users.users.pelican-panel = {
      isSystemUser = true;
      group = "pelican-panel";
      uid = 82;
    };

    services.nginx = {
      enable = true;
      virtualHosts."pelican-panel" = {
        serverName = "${cfg.subDomain}.${cfg.baseUrl}";
        forceSSL = true;
        useACMEHost = cfg.baseUrl;
        locations."/" = {
          proxyWebsockets = true;
          proxyPass = "http://127.0.0.1:${toString cfg.port}";
        };
      };
    };

    # Containers
    virtualisation.oci-containers.containers."pelican-panel" = {
      image = "ghcr.io/pelican-dev/panel:latest";
      environment = {
        XDG_DATA_HOME = "/pelican-data";
        APP_URL = "https://${cfg.subDomain}.${cfg.baseUrl}";
        ADMIN_EMAIL = "conquerix@shulker.link";
      };
      ports = [ "127.0.0.1:${toString cfg.port}:80" ];
      volumes = [
        "${cfg.stateDir}/data:/pelican-data"
        "${cfg.stateDir}/logs:/var/www/html/storage/logs"
        "${caddyFile}:/etc/caddy/Caddyfile"
      ];
    };

    environment.persistence = mkIf (cfg.impermanence) {
      "/nix/persist".directories = [
        {
          directory = "${cfg.stateDir}/data";
          mode = "u=rwx,g=rx,o=rx";
          user = "pelican-panel";
          group = "pelican-panel";
        }
        {
          directory = "${cfg.stateDir}/logs";
          mode = "u=rwx,g=rx,o=rx";
          user = "pelican-panel";
          group = "pelican-panel";
        }
      ];
    };

    # services.onepassword-secrets.secrets.pelican.panelEnv = {
    # reference = "op://Shulker/${config.networking.hostName}/Pelican panel env";
    # services = [ "docker" ];
    # };
  };
}
