{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.shulker.system.modules.paperless;
  composeServiceName = "paperless-compose";
  pullServiceName = "paperless-image-pull";
  stateServiceName = "paperless-state";
  environmentFile = config.services.onepassword-secrets.secrets.paperlessEnv.path;
  maintenanceLock = "/run/lock/paperless-maintenance.lock";
  composeYaml = pkgs.formats.yaml { };
  composeConfig = {
    name = "paperless";
    services = {
      broker = {
        container_name = "paperless_broker";
        image = cfg.valkeyImage;
        volumes = [ "${cfg.stateDir}/redis:/data" ];
        restart = "always";
        healthcheck = {
          test = [
            "CMD"
            "valkey-cli"
            "ping"
          ];
          interval = "30s";
          timeout = "10s";
          retries = 5;
        };
      };

      database = {
        container_name = "paperless_postgres";
        image = cfg.databaseImage;
        volumes = [ "${cfg.stateDir}/postgres:/var/lib/postgresql" ];
        environment = {
          POSTGRES_DB = "paperless";
          POSTGRES_USER = "paperless";
          POSTGRES_PASSWORD = "\${PAPERLESS_DB_PASSWORD:?PAPERLESS_DB_PASSWORD is required}";
          POSTGRES_INITDB_ARGS = "--data-checksums";
        };
        restart = "always";
        healthcheck = {
          test = [
            "CMD-SHELL"
            "pg_isready --username paperless --dbname paperless"
          ];
          interval = "30s";
          timeout = "10s";
          retries = 5;
        };
      };

      gotenberg = {
        container_name = "paperless_gotenberg";
        image = cfg.gotenbergImage;
        command = [
          "gotenberg"
          "--chromium-disable-javascript=true"
          "--chromium-allow-list=file:///tmp/.*"
        ];
        restart = "always";
      };

      tika = {
        container_name = "paperless_tika";
        image = cfg.tikaImage;
        restart = "always";
      };

      webserver = {
        container_name = "paperless_webserver";
        image = cfg.paperlessImage;
        depends_on = {
          broker.condition = "service_healthy";
          database.condition = "service_healthy";
          gotenberg.condition = "service_started";
          tika.condition = "service_started";
        };
        volumes = [
          "${cfg.stateDir}/data:/usr/src/paperless/data"
          "${cfg.stateDir}/media:/usr/src/paperless/media"
          "${cfg.stateDir}/export:/usr/src/paperless/export"
          "${cfg.stateDir}/consume:/usr/src/paperless/consume"
          "/etc/localtime:/etc/localtime:ro"
        ];
        ports = [ "${cfg.bindAddress}:${toString cfg.port}:8000/tcp" ];
        environment = {
          PAPERLESS_SECRET_KEY = "\${PAPERLESS_SECRET_KEY:?PAPERLESS_SECRET_KEY is required}";
          PAPERLESS_DBPASS = "\${PAPERLESS_DB_PASSWORD:?PAPERLESS_DB_PASSWORD is required}";
          PAPERLESS_DBHOST = "database";
          PAPERLESS_DBENGINE = "postgresql";
          PAPERLESS_DBNAME = "paperless";
          PAPERLESS_DBUSER = "paperless";
          PAPERLESS_REDIS = "redis://broker:6379";
          PAPERLESS_URL = cfg.publicUrl;
          PAPERLESS_TIME_ZONE = "Europe/Paris";
          PAPERLESS_OCR_LANGUAGE = cfg.ocrLanguage;
          PAPERLESS_OCR_LANGUAGES = "fra eng deu";
          PAPERLESS_DATE_PARSER_LANGUAGES = "fr+en+de";
          PAPERLESS_SEARCH_LANGUAGE = cfg.searchLanguage;
          PAPERLESS_EMPTY_TRASH_DELAY = toString cfg.trashDelayDays;
          PAPERLESS_ARCHIVE_FILE_GENERATION = "auto";
          PAPERLESS_CONSUMER_RECURSIVE = "true";
          PAPERLESS_CONSUMER_DELETE_DUPLICATES = "false";
          PAPERLESS_AUDIT_LOG_ENABLED = "true";
          PAPERLESS_TIKA_ENABLED = "1";
          PAPERLESS_TIKA_ENDPOINT = "http://tika:9998";
          PAPERLESS_TIKA_GOTENBERG_ENDPOINT = "http://gotenberg:3000";
          PAPERLESS_APPS = "allauth.socialaccount.providers.openid_connect";
          PAPERLESS_SOCIALACCOUNT_PROVIDERS = "\${PAPERLESS_SOCIALACCOUNT_PROVIDERS:?PAPERLESS_SOCIALACCOUNT_PROVIDERS is required}";
          PAPERLESS_ACCOUNT_ALLOW_SIGNUPS = "false";
          PAPERLESS_SOCIALACCOUNT_ALLOW_SIGNUPS = "true";
          PAPERLESS_SOCIAL_AUTO_SIGNUP = "true";
          PAPERLESS_DISABLE_REGULAR_LOGIN = "true";
          PAPERLESS_REDIRECT_LOGIN_TO_SSO = "true";
          PAPERLESS_SOCIAL_ACCOUNT_SYNC_GROUPS = "true";
          PAPERLESS_SOCIAL_ACCOUNT_SYNC_GROUPS_CLAIM = "groups";
          PAPERLESS_ACCOUNT_DEFAULT_HTTP_PROTOCOL = "https";
          PAPERLESS_ACCOUNT_EMAIL_VERIFICATION = "none";
          PAPERLESS_PROXY_SSL_HEADER = ''["HTTP_X_FORWARDED_PROTO", "https"]'';
          USERMAP_UID = toString cfg.uid;
          USERMAP_GID = toString cfg.gid;
        };
        restart = "always";
        healthcheck = {
          test = [
            "CMD"
            "curl"
            "-fsSL"
            "--max-time"
            "2"
            "http://localhost:8000"
          ];
          interval = "30s";
          timeout = "10s";
          retries = 5;
        };
      };
    };
  };
  composeFile = composeYaml.generate "paperless-compose.yml" composeConfig;
  composeEnvironment = pkgs.writeShellApplication {
    name = "paperless-compose-environment";
    runtimeInputs = [ pkgs.jq ];
    text = ''
      required_variables=(
        PAPERLESS_SECRET_KEY
        PAPERLESS_DB_PASSWORD
        PAPERLESS_OIDC_CLIENT_ID
        PAPERLESS_OIDC_CLIENT_SECRET
        PAPERLESS_FASTMAIL_USERNAME
        PAPERLESS_FASTMAIL_APP_PASSWORD
      )

      for variable in "''${required_variables[@]}"; do
        if [ -z "''${!variable:-}" ]; then
          echo "Required Paperless environment variable $variable is missing" >&2
          exit 65
        fi
        if [[ "''${!variable}" == *$'\n'* ]]; then
          echo "Required Paperless environment variable $variable must be a single line" >&2
          exit 65
        fi
      done

      PAPERLESS_SOCIALACCOUNT_PROVIDERS="$(${pkgs.jq}/bin/jq --compact-output --null-input \
        --arg client_id "$PAPERLESS_OIDC_CLIENT_ID" \
        --arg client_secret "$PAPERLESS_OIDC_CLIENT_SECRET" \
        --arg server_url ${lib.escapeShellArg "${cfg.oidcIssuer}/.well-known/openid-configuration"} \
        '{
          openid_connect: {
            SCOPE: ["openid", "profile", "email", "groups"],
            APPS: [
              {
                provider_id: "pocket-id",
                name: "Pocket ID",
                client_id: $client_id,
                secret: $client_secret,
                settings: {
                  server_url: $server_url,
                  token_auth_method: "client_secret_post"
                }
              }
            ]
          }
        }')"
      export PAPERLESS_SOCIALACCOUNT_PROVIDERS

      exec "$@"
    '';
  };
  healthCheck = pkgs.writeShellApplication {
    name = "paperless-health-check";
    runtimeInputs = [
      config.virtualisation.docker.package
      pkgs.coreutils
      pkgs.curl
      pkgs.systemd
      pkgs.util-linux
    ];
    text = ''
      exec 9>${maintenanceLock}
      flock 9

      if ! systemctl is-active --quiet ${composeServiceName}.service; then
        echo "Paperless Compose service is not active" >&2
        exit 1
      fi

      actual_services="$({
        docker ps \
          --filter label=com.docker.compose.project=paperless \
          --format '{{.Label "com.docker.compose.service"}}'
      } | sort)"
      expected_services="$(printf '%s\n' broker database gotenberg tika webserver | sort)"
      if [ "$actual_services" != "$expected_services" ]; then
        echo "Paperless does not have exactly five running Compose services" >&2
        exit 1
      fi

      curl --fail --silent --show-error --max-time 10 \
        http://${cfg.bindAddress}:${toString cfg.port}/ >/dev/null

      database_result="$(docker exec paperless_postgres \
        psql --username paperless --dbname paperless \
        --tuples-only --no-align --command 'SELECT 1')"
      if [ "$database_result" != 1 ]; then
        echo "Paperless PostgreSQL query failed" >&2
        exit 1
      fi

      broker_result="$(docker exec paperless_broker valkey-cli ping)"
      if [ "$broker_result" != PONG ]; then
        echo "Paperless broker did not respond" >&2
        exit 1
      fi

      docker exec paperless_webserver python -c '
      import urllib.request

      for name, url in (
          ("Tika", "http://tika:9998/version"),
          ("Gotenberg", "http://gotenberg:3000/health"),
      ):
          with urllib.request.urlopen(url, timeout=10) as response:
              if response.status != 200:
                  raise SystemExit(f"{name} health endpoint returned {response.status}")
      '

      paperless-validate-state
      echo "Paperless web, database, broker, Tika, Gotenberg, and storage are healthy"
    '';
  };
  schemaCheck = pkgs.writeShellApplication {
    name = "paperless-schema-check";
    runtimeInputs = [
      config.virtualisation.docker.package
      pkgs.systemd
      pkgs.util-linux
    ];
    text = ''
      exec 9>${maintenanceLock}
      flock 9

      if ! systemctl is-active --quiet ${composeServiceName}.service; then
        echo "Paperless Compose service is not active" >&2
        exit 1
      fi

      docker exec paperless_webserver python manage.py check --deploy
      docker exec paperless_webserver document_index reindex --if-needed
    '';
  };
in
{
  options.shulker.system.modules.paperless.composeFile = lib.mkOption {
    type = lib.types.package;
    readOnly = true;
    internal = true;
    description = "Generated Paperless Compose configuration.";
  };

  options.shulker.system.modules.paperless.composeConfig = lib.mkOption {
    type = lib.types.attrs;
    readOnly = true;
    internal = true;
    description = "Evaluated Paperless Compose configuration before YAML rendering.";
  };

  config = lib.mkIf cfg.enable {
    shulker.system.modules.paperless.composeConfig = composeConfig;
    shulker.system.modules.paperless.composeFile = composeFile;

    environment.systemPackages = [
      composeEnvironment
      healthCheck
      schemaCheck
    ];

    systemd.services.${pullServiceName} = {
      description = "Pull Paperless container images";
      wants = [ "network-online.target" ];
      requires = [
        "opnix-secrets.service"
        "docker.service"
        "${stateServiceName}.service"
      ];
      after = [
        "opnix-secrets.service"
        "docker.service"
        "${stateServiceName}.service"
        "network-online.target"
      ];
      unitConfig.ConditionFileNotEmpty = environmentFile;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        EnvironmentFile = environmentFile;
        ExecStartPre = "${composeEnvironment}/bin/paperless-compose-environment ${pkgs.docker-compose}/bin/docker-compose --project-name paperless --file ${composeFile} config --quiet";
        ExecStart = "${composeEnvironment}/bin/paperless-compose-environment ${pkgs.docker-compose}/bin/docker-compose --project-name paperless --file ${composeFile} pull";
        TimeoutStartSec = 1800;
        UMask = "0077";
      };
    };

    systemd.services.${composeServiceName} = {
      description = "Paperless document archive stack";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      requires = [
        "${pullServiceName}.service"
        "${stateServiceName}.service"
        "opnix-secrets.service"
        "docker.service"
      ];
      after = [
        "${pullServiceName}.service"
        "${stateServiceName}.service"
        "opnix-secrets.service"
        "docker.service"
        "network-online.target"
      ];
      unitConfig.ConditionFileNotEmpty = environmentFile;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        EnvironmentFile = environmentFile;
        ExecStartPre = "${composeEnvironment}/bin/paperless-compose-environment ${pkgs.docker-compose}/bin/docker-compose --project-name paperless --file ${composeFile} config --quiet";
        ExecStart = "${composeEnvironment}/bin/paperless-compose-environment ${pkgs.docker-compose}/bin/docker-compose --project-name paperless --file ${composeFile} up --detach --remove-orphans --wait --wait-timeout 300";
        ExecStop = "${composeEnvironment}/bin/paperless-compose-environment ${pkgs.docker-compose}/bin/docker-compose --project-name paperless --file ${composeFile} down --timeout 120";
        TimeoutStartSec = 360;
        TimeoutStopSec = 180;
        UMask = "0077";
      };
    };

    systemd.services.paperless-health-check = {
      description = "Check Paperless container and application health";
      after = [ "${composeServiceName}.service" ];
      unitConfig.RequiresMountsFor = cfg.stateDir;
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${healthCheck}/bin/paperless-health-check";
      };
    };

    systemd.timers.paperless-health-check = {
      description = "Check Paperless health every 15 minutes";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*:0/15";
        Persistent = true;
        RandomizedDelaySec = "5m";
      };
    };

    systemd.services.paperless-schema-check = {
      description = "Check Paperless database schema and search index";
      after = [ "${composeServiceName}.service" ];
      unitConfig.RequiresMountsFor = cfg.stateDir;
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${schemaCheck}/bin/paperless-schema-check";
      };
    };

    systemd.timers.paperless-schema-check = {
      description = "Check Paperless schema and index weekly";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "weekly";
        Persistent = true;
        RandomizedDelaySec = "1h";
      };
    };
  };
}
