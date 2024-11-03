{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.modules.pterodactyl.panel;

  # Command to create a new user in the panel:
  #   docker exec -it pterodactyl_panel php artisan p:user:make
in
{
  options.shulker.modules.pterodactyl.panel = {
    enable = mkEnableOption "Enable Pterodactyl Panel.";
    baseUrl = mkOption {
      type = types.str;
      default = "example.com";
      description = "Default url where pterodactyl will be accessible.";
    };
    subDomain = mkOption {
      type = types.str;
      default = "pterodactyl";
      description = "Default subdomain where pterodactyl will be accessible.";
    };
    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Default internal port to open pterodactyl.";
    };
    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/pterodactyl";
      description = "State Directory.";
    };
  };
  
  config = mkIf cfg.enable {
    
    # services.nginx = {
    #   enable = true;
    #   user = cfg.user;
    #   virtualHosts.pterodactyl-panel = {
    #     serverName = cfg.url;
    #     forceSSL = true;
    #     useACMEHost = "the-inbetween.net";
    #     root = "${cfg.dataDir}/public";
    #     extraConfig = ''
    #       index index.html index.htm index.php;
    #       client_max_body_size 500M;
    #     '';
    #     locations = {
    #       "~ \\.php$" = {
    #         extraConfig = ''
    #           fastcgi_split_path_info ^(.+\.php)(/.+)$;
    #           fastcgi_pass unix:${config.services.phpfpm.pools.pterodactyl.socket};
    #           include ${pkgs.nginx}/conf/fastcgi_params;
    #           fastcgi_index index.php;
    #           fastcgi_param PHP_VALUE "upload_max_filesize = 100M \n post_max_size=100M";
    #           fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    #           fastcgi_param HTTP_PROXY "";
    #           fastcgi_intercept_errors off;
    #           fastcgi_buffer_size 16k;
    #           fastcgi_buffers 4 16k;
    #           fastcgi_connect_timeout 300;
    #           fastcgi_send_timeout 300;
    #           fastcgi_read_timeout 300;
    #           proxy_set_header "Access-Control-Allow-Origin" *; 
    #           proxy_set_header "Access-Control-Allow-Methods" "GET, POST, OPTIONS"; 
    #           proxy_set_header "Access-Control-Allow-Headers" "Authorization"; 
    #         '';
    #       };
    #       "/" = {
    #         tryFiles = "$uri $uri/ /index.php?$query_string";
    #         extraConfig = ''
    #           proxy_set_header "Access-Control-Allow-Origin" *; 
    #           proxy_set_header "Access-Control-Allow-Methods" "GET, POST, OPTIONS"; 
    #           proxy_set_header "Access-Control-Allow-Headers" "Authorization";
    #         '';
    #       };
    #     };
    #   };
    # };

    services.nginx = {
      enable = true;
      virtualHosts."pterodactyl-panel" = {
        serverName = "${cfg.subDomain}.${cfg.baseUrl}";
        forceSSL = true;
        useACMEHost = cfg.baseUrl;
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString cfg.port}";
          extraConfig = ''
            proxy_set_header X-Real-IP $remote_addr;
            proxy_http_version 1.1;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header Host $host;
            proxy_set_header Connection "Upgrade";
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header X-Nginx-Proxy true;
            proxy_set_header X-Forwarded-Proto $scheme;
          '';
        };
      };
    };

    # Containers
    virtualisation.oci-containers.containers."pterodactyl-cache" = {
      image = "redis:alpine";
      log-driver = "journald";
      extraOptions = [
        "--network-alias=cache"
        "--network=pterodactyl_default"
      ];
    };
    
    virtualisation.oci-containers.containers."pterodactyl-database" = {
      image = "mariadb:10.5";
      environmentFiles = [ config.opnix.secrets.pterodactyl-db-env.path ];
      volumes = [
        "${cfg.stateDir}/database:/var/lib/mysql:rw"
      ];
      cmd = [ "--default-authentication-plugin=mysql_native_password" ];
      log-driver = "journald";
      extraOptions = [
        "--network-alias=database"
        "--network=pterodactyl_default"
      ];
    };

    opnix.secrets.pterodactyl-db-env = {
      source = ''
        MYSQL_DATABASE=panel
        MYSQL_PASSWORD={{ op://Shulker/${config.networking.hostName}/Secrets/Pterodactyl Panel DB Password }}
        MYSQL_ROOT_PASSWORD={{ op://Shulker/${config.networking.hostName}/Secrets/Pterodactyl Panel DB Root Password }}
        MYSQL_USER=pterodactyl
      '';
      mode = "0600";
    };
    
    virtualisation.oci-containers.containers."pterodactyl-panel" = {
      image = "ghcr.io/blueprintframework/blueprint:latest";
      environmentFiles = [ config.opnix.secrets.pterodactyl-panel-env.path ];
      volumes = [
        "${cfg.stateDir}/certs/:/etc/letsencrypt:rw"
        "${cfg.stateDir}/logs/:/app/storage/logs:rw"
        "${cfg.stateDir}/nginx/:/etc/nginx/http.d:rw"
        "${cfg.stateDir}/var/:/app/var:rw"
        "${cfg.stateDir}/extensions/:/blueprint_extensions:rw"
      ];
      ports = [
        "127.0.0.1:${toString cfg.port}:80/tcp"
      ];
      dependsOn = [
        "pterodactyl-cache"
        "pterodactyl-database"
      ];
      log-driver = "journald";
      extraOptions = [
        "--network-alias=panel"
        "--network=pterodactyl_default"
      ];
    };

    opnix.secrets.pterodactyl-panel-env = {
      source = ''
        APP_ENV=production
        APP_ENVIRONMENT_ONLY=false
        APP_SERVICE_AUTHOR=conquerix@shulker.link
        APP_TIMEZONE=UTC
        APP_URL=http://127.0.0.1
        CACHE_DRIVER=redis
        DB_HOST=database
        DB_PASSWORD={{ op://Shulker/${config.networking.hostName}/Secrets/Pterodactyl Panel DB Password }}
        DB_PORT=3306
        QUEUE_DRIVER=redis
        REDIS_HOST=cache
        SESSION_DRIVER=redis
      '';
      mode = "0600";
    };

    # Networks
    systemd.services."docker-network-pterodactyl_default" = {
      path = [ pkgs.docker ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStop = "docker network rm -f pterodactyl_default";
      };
      script = ''
        docker network inspect pterodactyl_default || docker network create pterodactyl_default --subnet=172.20.0.0/16
      '';
      partOf = [ "docker-compose-pterodactyl-root.target" ];
      wantedBy = [ "docker-compose-pterodactyl-root.target" ];
    };

    # Systemd services modifications for the networks
    systemd.services."docker-pterodactyl-cache" = {
      serviceConfig = {
        Restart = lib.mkOverride 90 "always";
        RestartMaxDelaySec = lib.mkOverride 90 "1m";
        RestartSec = lib.mkOverride 90 "100ms";
        RestartSteps = lib.mkOverride 90 9;
      };
      after = [
        "docker-network-pterodactyl_default.service"
      ];
      requires = [
        "docker-network-pterodactyl_default.service"
      ];
      partOf = [
        "docker-compose-pterodactyl-root.target"
      ];
      wantedBy = [
        "docker-compose-pterodactyl-root.target"
      ];
    };

    systemd.services."docker-pterodactyl-database" = {
      serviceConfig = {
        Restart = lib.mkOverride 90 "always";
        RestartMaxDelaySec = lib.mkOverride 90 "1m";
        RestartSec = lib.mkOverride 90 "100ms";
        RestartSteps = lib.mkOverride 90 9;
      };
      after = [
        "docker-network-pterodactyl_default.service"
      ];
      requires = [
        "docker-network-pterodactyl_default.service"
      ];
      partOf = [
        "docker-compose-pterodactyl-root.target"
      ];
      wantedBy = [
        "docker-compose-pterodactyl-root.target"
      ];
    };

    systemd.services."docker-pterodactyl-panel" = {
      serviceConfig = {
        Restart = lib.mkOverride 90 "always";
        RestartMaxDelaySec = lib.mkOverride 90 "1m";
        RestartSec = lib.mkOverride 90 "100ms";
        RestartSteps = lib.mkOverride 90 9;
      };
      after = [
        "docker-network-pterodactyl_default.service"
      ];
      requires = [
        "docker-network-pterodactyl_default.service"
      ];
      partOf = [
        "docker-compose-pterodactyl-root.target"
      ];
      wantedBy = [
        "docker-compose-pterodactyl-root.target"
      ];
    };

    # Root service
    # When started, this will automatically create all resources and start
    # the containers. When stopped, this will teardown all resources.
    systemd.targets."docker-compose-pterodactyl-root" = {
      unitConfig = {
        Description = "Root target generated by compose2nix.";
      };
      wantedBy = [ "multi-user.target" ];
    };

    environment.persistence."/nix/persist".directories = mkIf (config.shulker.modules.impermanence.enable) [ 
      "${cfg.stateDir}"
    ];
  };
}
