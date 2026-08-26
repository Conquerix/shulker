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
    appUrl = mkOption {
      type = types.str;
      default = "example.com";
      description = "Url where pelican panel will be accessible.";
    };
    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/pelican/panel";
      description = "State Directory.";
    };
    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Internal port to open pelican panel.";
    };
  };

  config = mkIf cfg.enable {

    shulker.system.modules.containers.enable = true;

    users.groups.pelican-panel.gid = 82;
    users.users.pelican-panel = {
      isSystemUser = true;
      group = "pelican-panel";
      uid = 82;
    };
    systemd.tmpfiles.rules =
      map (directory: "d ${cfg.stateDir}/${directory} 0750 pelican-panel pelican-panel - -")
        [
          "data"
          "logs"
          "plugins"
        ];

    # Containers
    virtualisation.oci-containers.containers."pelican-panel" = {
      image = "ghcr.io/pelican-dev/panel:v1.0.0-beta31@sha256:5c57b17627eb134d52c0589bc1eaccf198b811a47c33cceb6416ff29504b2fa5";
      environment = {
        XDG_DATA_HOME = "/pelican-data";
        APP_URL = cfg.appUrl;
        ADMIN_EMAIL = "conquerix@shulker.link";
      };
      ports = [ "127.0.0.1:${toString cfg.port}:80" ];
      volumes = [
        "${cfg.stateDir}/data:/pelican-data"
        "${cfg.stateDir}/logs:/var/www/html/storage/logs"
        "${cfg.stateDir}/plugins:/var/www/html/plugins"
        "${caddyFile}:/etc/caddy/Caddyfile"
      ];
    };

    environment.persistence = mkIf cfg.impermanence {
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
        {
          directory = "${cfg.stateDir}/plugins";
          mode = "u=rwx,g=rx,o=rx";
          user = "pelican-panel";
          group = "pelican-panel";
        }
      ];
    };

    shulker.system.modules.backup.dirs = [ cfg.stateDir ];
    services.borgmatic.settings.sqlite_databases = [
      {
        name = "pelican-panel-db";
        path = "${cfg.stateDir}/data/database/database.sqlite";
      }
    ];
  };
}
