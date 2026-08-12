{ pkgs }:

{
  projectName,
  containerNames,
  networkName,
  stateDir,
  appRuntimeDir,
  metadataRuntimeDir,
  bindAddress,
  ports,
  urls,
  images,
  metadata,
  publishApplicationPorts ? true,
  enableExternalEgress ? true,
  serviceLabels ? { },
  seafileExtraVolumes ? [ ],
  onlyOfficeExtraVolumes ? [ ],
}:

let
  required = variable: "\${${variable}:?${variable} is required}";
  redisUid = 999;
  redisGid = 1000;
  redisStartScriptText = ''
    #!/bin/sh
    set -eu

    umask 077
    config=/run/redis/redis.conf
    cleanup() {
      rm -f "$config"
    }
    trap cleanup EXIT HUP INT TERM

    mkdir -p /run/redis
    chown ${toString redisUid}:${toString redisGid} /run/redis
    chmod 0700 /run/redis
    {
      printf 'requirepass %s\n' "$REDIS_PASSWORD"
      printf 'save ""\n'
      printf 'appendonly no\n'
      printf 'dir /run/redis\n'
    } >"$config"
    chown ${toString redisUid}:${toString redisGid} "$config"
    chmod 0600 "$config"
    /usr/bin/setpriv \
      --reuid ${toString redisUid} --regid ${toString redisGid} --clear-groups \
      test -r "$config"
    unset REDIS_PASSWORD
    trap - EXIT HUP INT TERM
    exec /usr/bin/setpriv \
      --reuid ${toString redisUid} --regid ${toString redisGid} --clear-groups \
      /usr/local/bin/redis-server /run/redis/redis.conf
  '';
  redisStartScript = pkgs.writeTextFile {
    name = "seafile-start-redis";
    executable = true;
    text = redisStartScriptText;
  };
  onlyOfficeConfig = (pkgs.formats.json { }).generate "local-production-linux.json" {
    services.CoAuthoring.autoAssembly = {
      enable = true;
      interval = "5m";
    };
  };
  privateNetwork = [ networkName ];
  egressNetworkName = "${networkName}-egress";
  applicationNetworks =
    privateNetwork ++ (if enableExternalEgress then [ egressNetworkName ] else [ ]);
  databaseEnvironment = {
    MARIADB_AUTO_UPGRADE = "1";
    MYSQL_LOG_CONSOLE = "true";
  };
  seafileEnvironment = {
    SEAFILE_MYSQL_DB_HOST = "database";
    SEAFILE_MYSQL_DB_PORT = "3306";
    SEAFILE_MYSQL_DB_USER = "seafile";
    SEAFILE_MYSQL_DB_PASSWORD = required "SEAFILE_MYSQL_DB_PASSWORD";
    SEAFILE_MYSQL_DB_CCNET_DB_NAME = "ccnet_db";
    SEAFILE_MYSQL_DB_SEAFILE_DB_NAME = "seafile_db";
    SEAFILE_MYSQL_DB_SEAHUB_DB_NAME = "seahub_db";
    CACHE_PROVIDER = "redis";
    REDIS_HOST = "redis";
    REDIS_PORT = "6379";
    REDIS_PASSWORD = required "REDIS_PASSWORD";
    SEAFILE_SERVER_HOSTNAME = urls.hostname;
    SEAFILE_SERVER_PROTOCOL = "https";
    TIME_ZONE = "Europe/Paris";
    ENABLE_GO_FILESERVER = "true";
    ENABLE_SEADOC = "false";
    ENABLE_NOTIFICATION_SERVER = "true";
    INNER_NOTIFICATION_SERVER_URL = urls.notificationInternal;
    NOTIFICATION_SERVER_URL = urls.notificationPublic;
    ENABLE_SEAFILE_AI = "false";
    ENABLE_FACE_RECOGNITION = "false";
    SEAF_SERVER_STORAGE_TYPE = "disk";
    MD_FILE_COUNT_LIMIT = toString metadata.fileCountLimit;
    NON_ROOT = "false";
    JWT_PRIVATE_KEY = required "JWT_PRIVATE_KEY";
    SEAHUB_SECRET_KEY = required "SEAHUB_SECRET_KEY";
    INIT_SEAFILE_ADMIN_EMAIL = required "INIT_SEAFILE_ADMIN_EMAIL";
    INIT_SEAFILE_ADMIN_PASSWORD = required "INIT_SEAFILE_ADMIN_PASSWORD";
    SEAFILE_OAUTH_CLIENT_ID = required "SEAFILE_OAUTH_CLIENT_ID";
    SEAFILE_OAUTH_CLIENT_SECRET = required "SEAFILE_OAUTH_CLIENT_SECRET";
    ONLYOFFICE_JWT_SECRET = required "ONLYOFFICE_JWT_SECRET";
  };
  composeConfig = {
    name = projectName;
    services = {
      database = {
        container_name = containerNames.database;
        image = images.database;
        restart = "no";
        labels = serviceLabels;
        networks = privateNetwork;
        environment = databaseEnvironment;
        volumes = [ "${stateDir}/database:/var/lib/mysql" ];
        healthcheck = {
          test = [
            "CMD"
            "/usr/bin/timeout"
            "--signal=TERM"
            "--kill-after=1s"
            "4s"
            "/usr/local/bin/healthcheck.sh"
            "--connect"
            "--mariadbupgrade"
            "--innodb_initialized"
          ];
          interval = "20s";
          start_period = "30s";
          timeout = "8s";
          retries = 10;
        };
      };
      redis = {
        container_name = containerNames.redis;
        image = images.redis;
        restart = "no";
        labels = serviceLabels;
        networks = privateNetwork;
        environment.REDIS_PASSWORD = required "REDIS_PASSWORD";
        entrypoint = [ "/usr/local/sbin/seafile-start-redis" ];
        command = [ "/run/redis/redis.conf" ];
        tmpfs = [ "/run/redis" ];
        volumes = [
          {
            type = "bind";
            source = toString redisStartScript;
            target = "/usr/local/sbin/seafile-start-redis";
            read_only = true;
            bind.create_host_path = false;
          }
        ];
        healthcheck = {
          test = [
            "CMD-SHELL"
            "REDISCLI_AUTH=\"$$REDIS_PASSWORD\" redis-cli ping | grep -qx PONG"
          ];
          interval = "20s";
          timeout = "5s";
          retries = 10;
        };
      };
      seafile = {
        container_name = containerNames.seafile;
        image = images.seafile;
        restart = "no";
        labels = serviceLabels;
        networks = applicationNetworks;
        ports =
          if publishApplicationPorts then [ "${bindAddress}:${toString ports.seafile}:80/tcp" ] else [ ];
        environment = seafileEnvironment;
        volumes = [
          "${stateDir}/shared:/shared"
          "${appRuntimeDir}:/run/seafile:ro"
        ]
        ++ seafileExtraVolumes;
        depends_on = {
          database.condition = "service_healthy";
          redis.condition = "service_healthy";
        };
        healthcheck = {
          test = [
            "CMD-SHELL"
            "curl --fail --silent http://127.0.0.1:80/ >/dev/null"
          ];
          interval = "30s";
          timeout = "10s";
          retries = 10;
          start_period = "30m";
        };
      };
      seasearch = {
        container_name = containerNames.seasearch;
        image = images.seasearch;
        restart = "no";
        labels = serviceLabels;
        networks = privateNetwork;
        environment = {
          SS_MAX_OBJ_CACHE_SIZE = "10GB";
          SS_STORAGE_TYPE = "disk";
          SS_LOG_TO_STDOUT = "true";
          SS_LOG_LEVEL = "info";
        };
        volumes = [ "${stateDir}/search:/opt/seasearch/data" ];
        healthcheck = {
          test = [
            "CMD-SHELL"
            "kill -0 1"
          ];
          interval = "30s";
          timeout = "5s";
          retries = 5;
        };
      };
      notification = {
        container_name = containerNames.notification;
        image = images.notification;
        restart = "no";
        labels = serviceLabels;
        networks = applicationNetworks;
        ports =
          if publishApplicationPorts then
            [ "${bindAddress}:${toString ports.notification}:8083/tcp" ]
          else
            [ ];
        environment = {
          SEAFILE_MYSQL_DB_HOST = "database";
          SEAFILE_MYSQL_DB_PORT = "3306";
          SEAFILE_MYSQL_DB_USER = "seafile";
          SEAFILE_MYSQL_DB_PASSWORD = required "SEAFILE_MYSQL_DB_PASSWORD";
          SEAFILE_MYSQL_DB_CCNET_DB_NAME = "ccnet_db";
          SEAFILE_MYSQL_DB_SEAFILE_DB_NAME = "seafile_db";
          JWT_PRIVATE_KEY = required "JWT_PRIVATE_KEY";
          SEAFILE_LOG_TO_STDOUT = "true";
          NOTIFICATION_SERVER_LOG_LEVEL = "info";
        };
        volumes = [ "${stateDir}/shared/seafile/logs:/shared/seafile/logs" ];
        depends_on = {
          database.condition = "service_healthy";
          seafile.condition = "service_healthy";
        };
        healthcheck = {
          test = [
            "CMD"
            "/bin/bash"
            "-ec"
            "exec 3<>/dev/tcp/127.0.0.1/8083; printf 'GET /ping HTTP/1.0\\r\\nHost: 127.0.0.1\\r\\nConnection: close\\r\\n\\r\\n' >&3; IFS= read -r -u 3 status; [[ \"$$status\" == HTTP/*\" 200 \"* ]]; while IFS= read -r -u 3 header; do [[ \"$$header\" != $$'\\r' ]] || break; done; body=; IFS= read -r -u 3 body || [[ -n \"$$body\" ]]; [[ \"$$body\" == '{\"ret\": \"pong\"}' ]]"
          ];
          interval = "30s";
          timeout = "5s";
          retries = 5;
        };
      };
      metadata = {
        container_name = containerNames.metadata;
        image = images.metadata;
        restart = "no";
        labels = serviceLabels;
        networks = privateNetwork;
        environment = {
          JWT_PRIVATE_KEY = required "JWT_PRIVATE_KEY";
          SEAFILE_MYSQL_DB_HOST = "database";
          SEAFILE_MYSQL_DB_PORT = "3306";
          SEAFILE_MYSQL_DB_USER = "seafile";
          SEAFILE_MYSQL_DB_PASSWORD = required "SEAFILE_MYSQL_DB_PASSWORD";
          SEAFILE_MYSQL_DB_SEAFILE_DB_NAME = "seafile_db";
          SEAFILE_LOG_TO_STDOUT = "true";
          MD_MAX_CACHE_SIZE = metadata.cacheSize;
          MD_CHECK_UPDATE_INTERVAL = metadata.checkUpdateInterval;
          MD_FILE_COUNT_LIMIT = toString metadata.fileCountLimit;
          SEAF_SERVER_STORAGE_TYPE = "disk";
          MD_STORAGE_TYPE = "disk";
          CACHE_PROVIDER = "redis";
          REDIS_HOST = "redis";
          REDIS_PORT = "6379";
          REDIS_PASSWORD = required "REDIS_PASSWORD";
        };
        volumes = [
          "${stateDir}/shared:/shared"
          "${metadataRuntimeDir}:/run/seafile:ro"
        ];
        depends_on = {
          database.condition = "service_healthy";
          redis.condition = "service_healthy";
          seafile.condition = "service_healthy";
        };
        healthcheck = {
          test = [
            "CMD-SHELL"
            "test -r /run/seafile/seafile.conf && kill -0 1"
          ];
          interval = "30s";
          timeout = "5s";
          retries = 5;
        };
      };
      onlyoffice = {
        container_name = containerNames.onlyoffice;
        image = images.onlyoffice;
        restart = "no";
        labels = serviceLabels;
        networks = applicationNetworks;
        ports =
          if publishApplicationPorts then [ "${bindAddress}:${toString ports.onlyoffice}:80/tcp" ] else [ ];
        environment = {
          JWT_ENABLED = "true";
          JWT_SECRET = required "ONLYOFFICE_JWT_SECRET";
          EXAMPLE_ENABLED = "false";
        };
        volumes = [
          {
            type = "bind";
            source = "${stateDir}/onlyoffice/logs";
            target = "/var/log/onlyoffice";
            bind.create_host_path = false;
          }
          {
            type = "bind";
            source = "${stateDir}/onlyoffice/data";
            target = "/var/www/onlyoffice/Data";
            bind.create_host_path = false;
          }
          {
            type = "bind";
            source = "${stateDir}/onlyoffice/lib";
            target = "/var/lib/onlyoffice";
            bind.create_host_path = false;
          }
          {
            type = "bind";
            source = toString onlyOfficeConfig;
            target = "/etc/onlyoffice/documentserver/local-production-linux.json";
            read_only = true;
            bind.create_host_path = false;
          }
        ]
        ++ onlyOfficeExtraVolumes;
        healthcheck = {
          test = [
            "CMD-SHELL"
            "test \"$(curl --fail --silent http://127.0.0.1/healthcheck)\" = true"
          ];
          interval = "30s";
          timeout = "10s";
          retries = 5;
        };
      };
    };
    networks = {
      ${networkName} = {
        name = networkName;
        internal = true;
      };
    }
    // (
      if enableExternalEgress then
        {
          ${egressNetworkName} = {
            name = egressNetworkName;
            internal = false;
          };
        }
      else
        { }
    );
  };
  bootstrapComposeConfig.services = {
    database.environment.MYSQL_ROOT_PASSWORD = required "INIT_SEAFILE_MYSQL_ROOT_PASSWORD";
    seafile.environment.INIT_SEAFILE_MYSQL_ROOT_PASSWORD = required "INIT_SEAFILE_MYSQL_ROOT_PASSWORD";
    seasearch.environment = {
      SS_FIRST_ADMIN_USER = required "INIT_SS_ADMIN_USER";
      SS_FIRST_ADMIN_PASSWORD = required "INIT_SS_ADMIN_PASSWORD";
    };
  };
in
{
  inherit
    bootstrapComposeConfig
    composeConfig
    onlyOfficeConfig
    redisStartScript
    redisStartScriptText
    ;
  composeFile = (pkgs.formats.yaml { }).generate "${projectName}-compose.yml" composeConfig;
  bootstrapComposeFile =
    (pkgs.formats.yaml { }).generate "${projectName}-bootstrap-compose.yml"
      bootstrapComposeConfig;
}
