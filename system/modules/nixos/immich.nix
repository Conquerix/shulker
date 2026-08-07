{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.shulker.system.modules.immich;
  composeServiceName = "immich-compose";
  pullServiceName = "immich-image-pull";
  stateServiceName = "immich-state";
  environmentFile = config.services.onepassword-secrets.secrets.immichEnv.path;
  snapshot = "${cfg.dataset}@${cfg.backupSnapshotName}";
  snapshotPath = "${cfg.stateDir}/.zfs/snapshot/${cfg.backupSnapshotName}";
  maintenanceLock = "/run/lock/immich-maintenance.lock";
  composeYaml = pkgs.formats.yaml { };
  composeFile = composeYaml.generate "immich-compose.yml" {
    name = "immich";
    services = {
      immich-server = {
        container_name = "immich_server";
        image = cfg.serverImage;
        devices = [ "/dev/dri:/dev/dri" ];
        group_add = [
          (toString config.users.groups.video.gid)
          (toString config.users.groups.render.gid)
        ];
        volumes = [
          "${cfg.stateDir}/library:/data"
          "/run/immich/immich.json:/etc/immich/immich.json:ro"
          "/etc/localtime:/etc/localtime:ro"
        ];
        environment = {
          IMMICH_ALLOW_SETUP = if cfg.allowSetup then "true" else "false";
          IMMICH_CONFIG_FILE = "/etc/immich/immich.json";
          DB_HOSTNAME = "database";
          DB_USERNAME = "postgres";
          DB_DATABASE_NAME = "immich";
          DB_PASSWORD = "\${DB_PASSWORD:?DB_PASSWORD is required}";
          REDIS_HOSTNAME = "redis";
        };
        ports = [ "${cfg.bindAddress}:${toString cfg.port}:2283/tcp" ];
        depends_on = [
          "redis"
          "database"
        ];
        restart = "always";
        healthcheck.disable = false;
      };

      immich-machine-learning = {
        container_name = "immich_machine_learning";
        image = cfg.machineLearningImage;
        devices = [ "/dev/dri:/dev/dri" ];
        device_cgroup_rules = [ "c 189:* rmw" ];
        group_add = [
          (toString config.users.groups.video.gid)
          (toString config.users.groups.render.gid)
        ];
        volumes = [
          "${cfg.stateDir}/model-cache:/cache"
          "/dev/bus/usb:/dev/bus/usb"
        ];
        restart = "always";
        healthcheck.disable = false;
      };

      redis = {
        container_name = "immich_redis";
        image = cfg.valkeyImage;
        healthcheck.test = [
          "CMD-SHELL"
          "redis-cli ping || exit 1"
        ];
        restart = "always";
      };

      database = {
        container_name = "immich_postgres";
        image = cfg.databaseImage;
        environment = {
          POSTGRES_PASSWORD = "\${DB_PASSWORD:?DB_PASSWORD is required}";
          POSTGRES_USER = "postgres";
          POSTGRES_DB = "immich";
          POSTGRES_INITDB_ARGS = "--data-checksums";
        };
        volumes = [ "${cfg.stateDir}/postgres:/var/lib/postgresql/data" ];
        shm_size = "128mb";
        restart = "always";
        healthcheck.disable = false;
      };
    };
  };
  renderConfig = pkgs.writeShellApplication {
    name = "immich-render-config";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
    ];
    text = ''
      readonly runtime_directory=/run/immich
      readonly destination="$runtime_directory/immich.json"

      if [ -z "''${DB_PASSWORD:-}" ]; then
        echo "Immich DB_PASSWORD is missing" >&2
        exit 65
      fi
      if [ -z "''${OAUTH_CLIENT_ID:-}" ]; then
        echo "Immich OAUTH_CLIENT_ID is missing" >&2
        exit 65
      fi
      if [ -z "''${OAUTH_CLIENT_SECRET:-}" ]; then
        echo "Immich OAUTH_CLIENT_SECRET is missing" >&2
        exit 65
      fi

      umask 077
      temporary_file="$(mktemp "$runtime_directory/immich.json.XXXXXX")"
      cleanup() {
        rm -f "$temporary_file"
      }
      trap cleanup EXIT

      jq -n '
        {
          backup: {
            database: {
              cronExpression: "0 02 * * *",
              enabled: true,
              keepLastAmount: 14
            }
          },
          oauth: {
            autoLaunch: true,
            autoRegister: true,
            buttonText: "Sign in with Pocket ID",
            clientId: env.OAUTH_CLIENT_ID,
            clientSecret: env.OAUTH_CLIENT_SECRET,
            defaultStorageQuota: null,
            enabled: true,
            issuerUrl: ${builtins.toJSON cfg.oidcIssuer},
            mobileOverrideEnabled: false,
            mobileRedirectUri: "",
            profileSigningAlgorithm: "none",
            roleClaim: "immich_role",
            scope: "openid email profile",
            signingAlgorithm: "RS256",
            storageLabelClaim: "preferred_username",
            storageQuotaClaim: "immich_quota",
            timeout: 30000,
            tokenEndpointAuthMethod: "client_secret_post"
          },
          passwordLogin: {
            enabled: false
          },
          server: {
            externalDomain: ${builtins.toJSON cfg.publicUrl}
          },
          storageTemplate: {
            enabled: false,
            hashVerificationEnabled: true
          }
        }
      ' > "$temporary_file"

      jq -e '
        .oauth.enabled == true
        and .oauth.clientId != ""
        and .oauth.clientSecret != ""
        and .passwordLogin.enabled == false
        and .storageTemplate.enabled == false
      ' "$temporary_file" >/dev/null
      chmod 0400 "$temporary_file"
      mv -f "$temporary_file" "$destination"
      trap - EXIT
    '';
  };
  backupPrepare = pkgs.writeShellApplication {
    name = "immich-backup-prepare";
    runtimeInputs = [
      config.boot.zfs.package
      pkgs.coreutils
      pkgs.systemd
      pkgs.util-linux
    ];
    text = ''
      readonly dataset=${lib.escapeShellArg cfg.dataset}
      readonly snapshot_name=${lib.escapeShellArg cfg.backupSnapshotName}
      readonly snapshot=${lib.escapeShellArg snapshot}
      readonly service=${lib.escapeShellArg "${composeServiceName}.service"}

      if [ "$snapshot" != "$dataset@$snapshot_name" ]; then
        echo "Refusing unexpected Immich snapshot target" >&2
        exit 64
      fi

      exec 9>${maintenanceLock}
      flock 9

      if zfs list -H -o name -t snapshot "$snapshot" >/dev/null 2>&1; then
        zfs destroy "$snapshot"
      fi

      if ! systemctl is-active --quiet "$service"; then
        echo "Immich must be active before taking its backup snapshot" >&2
        exit 1
      fi

      service_stopped=0
      snapshot_created=0
      recover() {
        status=$?
        trap - EXIT
        if [ "$service_stopped" -eq 1 ]; then
          systemctl start "$service" || true
        fi
        if [ "$snapshot_created" -eq 1 ] && [ "$status" -ne 0 ]; then
          zfs destroy "$snapshot" || true
        fi
        exit "$status"
      }
      trap recover EXIT
      trap 'exit 1' INT TERM

      systemctl stop "$service"
      service_stopped=1
      zfs snapshot "$snapshot"
      snapshot_created=1

      if [ "''${IMMICH_BACKUP_TEST_FAIL_AFTER_SNAPSHOT:-0}" = 1 ]; then
        echo "Injecting the requested Immich post-snapshot backup failure" >&2
        exit 75
      fi

      systemctl start "$service"
      systemctl is-active --quiet "$service"
      service_stopped=0

      trap - EXIT INT TERM
    '';
  };
  backupCleanup = pkgs.writeShellApplication {
    name = "immich-backup-cleanup";
    runtimeInputs = [
      config.boot.zfs.package
      pkgs.util-linux
    ];
    text = ''
      readonly dataset=${lib.escapeShellArg cfg.dataset}
      readonly snapshot_name=${lib.escapeShellArg cfg.backupSnapshotName}
      readonly snapshot=${lib.escapeShellArg snapshot}

      if [ "$snapshot" != "$dataset@$snapshot_name" ]; then
        echo "Refusing unexpected Immich snapshot target" >&2
        exit 64
      fi

      exec 9>${maintenanceLock}
      flock 9

      if zfs list -H -o name -t snapshot "$snapshot" >/dev/null 2>&1; then
        zfs destroy "$snapshot"
      fi
    '';
  };
  healthCheck = pkgs.writeShellApplication {
    name = "immich-health-check";
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
        exit 0
      fi

      curl --fail --silent --show-error \
        http://${cfg.bindAddress}:${toString cfg.port}/api/server/ping >/dev/null

      actual_services="$(
        DB_PASSWORD=health-check-only \
          ${pkgs.docker-compose}/bin/docker-compose \
          --project-name immich \
          --file ${composeFile} \
          ps --status running --services | sort
      )"
      expected_services="$(printf '%s\n' \
        database \
        immich-machine-learning \
        immich-server \
        redis | sort)"
      if [ "$actual_services" != "$expected_services" ]; then
        echo "Immich does not have exactly four running Compose services" >&2
        exit 1
      fi

      for container in \
        immich_server \
        immich_machine_learning \
        immich_redis \
        immich_postgres
      do
        health_status="$(docker inspect --format '{{.State.Health.Status}}' "$container")"
        if [ "$health_status" != healthy ]; then
          echo "$container is not healthy" >&2
          exit 1
        fi
      done
    '';
  };
  schemaCheck = pkgs.writeShellApplication {
    name = "immich-schema-check";
    runtimeInputs = [
      config.virtualisation.docker.package
      pkgs.systemd
      pkgs.util-linux
    ];
    text = ''
      exec 9>${maintenanceLock}
      flock 9

      if ! systemctl is-active --quiet ${composeServiceName}.service; then
        exit 0
      fi

      docker exec immich_server immich-admin schema-check
    '';
  };
in
{
  options.shulker.system.modules.immich = {
    enable = lib.mkEnableOption "Immich family photo and video storage";

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/immich";
      description = "Mount point containing all persistent Immich state.";
    };

    dataset = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Dedicated ZFS dataset mounted at stateDir.";
    };

    datasetQuotaBytes = lib.mkOption {
      type = lib.types.ints.positive;
      default = 1649267441664;
      description = "Expected ZFS dataset quota in bytes.";
    };

    bindAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Host address on which to publish the Immich HTTP listener.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 23237;
      description = "Loopback HTTP port intended for Pangolin.";
    };

    publicUrl = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "https://photos.example.com";
      description = "Public HTTPS URL used by Immich web and native clients.";
    };

    oidcIssuer = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "https://sso.example.com";
      description = "External OpenID Connect issuer used for Immich authentication.";
    };

    allowSetup = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Temporarily allow creation of the first Immich administrator.";
    };

    backupSnapshotName = lib.mkOption {
      type = lib.types.str;
      default = "borgmatic";
      description = "Exact ZFS snapshot name reserved for Borgmatic backups.";
    };

    backUpData = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Include a consistent ZFS snapshot of all Immich state in Borgmatic.";
    };

    serverImage = lib.mkOption {
      type = lib.types.str;
      default = "ghcr.io/immich-app/immich-server:v3.1.0@sha256:b434cb9287eea1471c9974845914d4dd328c9c2d652e446ed4930f99944f0ceb";
      description = "Digest-pinned Immich server container image.";
    };

    machineLearningImage = lib.mkOption {
      type = lib.types.str;
      default = "ghcr.io/immich-app/immich-machine-learning:v3.1.0-openvino@sha256:4b6ef958e7749fc548377bb23ee219c09c74da8decee080d76dc6a388c39b013";
      description = "Digest-pinned Immich OpenVINO machine-learning image.";
    };

    valkeyImage = lib.mkOption {
      type = lib.types.str;
      default = "docker.io/valkey/valkey:9@sha256:8e8d64b405ce18f41b8e5ee20aa4687a8ed0022d1298f2ce31cdcf3a76e09411";
      description = "Digest-pinned Valkey image used by Immich.";
    };

    databaseImage = lib.mkOption {
      type = lib.types.str;
      default = "ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0@sha256:bcf63357191b76a916ae5eb93464d65c07511da41e3bf7a8416db519b40b1c23";
      description = "Digest-pinned PostgreSQL and VectorChord image used by Immich.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.hasPrefix "https://" cfg.publicUrl;
        message = "Immich publicUrl must use HTTPS.";
      }
      {
        assertion = lib.hasPrefix "https://" cfg.oidcIssuer;
        message = "Immich oidcIssuer must use HTTPS.";
      }
      {
        assertion = lib.elem cfg.bindAddress [
          "127.0.0.1"
          "[::1]"
        ];
        message = "Immich must remain bound to host loopback and be exposed through Pangolin.";
      }
      {
        assertion = cfg.stateDir != "" && lib.hasPrefix "/" cfg.stateDir;
        message = "Immich stateDir must be an absolute path.";
      }
      {
        assertion = cfg.dataset != "";
        message = "Immich requires a dedicated ZFS dataset.";
      }
      {
        assertion = !(lib.elem "zfsutil" config.fileSystems.${cfg.stateDir}.options);
        message = "Immich uses a legacy-mounted ZFS dataset and must not enable zfsutil.";
      }
      {
        assertion = !cfg.backUpData || config.shulker.system.modules.backup.enable;
        message = "Immich backup coverage requires the Borgmatic backup module.";
      }
      {
        assertion =
          cfg.backupSnapshotName != ""
          && !(lib.hasInfix "/" cfg.backupSnapshotName)
          && !(lib.hasInfix "@" cfg.backupSnapshotName);
        message = "Immich backupSnapshotName must be a simple ZFS snapshot component.";
      }
      {
        assertion = lib.all (image: lib.hasInfix "@sha256:" image) [
          cfg.serverImage
          cfg.machineLearningImage
          cfg.valkeyImage
          cfg.databaseImage
        ];
        message = "Every Immich Compose image must be pinned by digest.";
      }
    ];

    shulker.system.modules.containers.enable = true;

    environment.systemPackages = [
      backupPrepare
      backupCleanup
    ];

    fileSystems.${cfg.stateDir} = {
      device = cfg.dataset;
      fsType = "zfs";
    };

    systemd.services.${stateServiceName} = {
      description = "Prepare persistent Immich state";
      before = [ "${composeServiceName}.service" ];
      unitConfig.RequiresMountsFor = cfg.stateDir;
      path = [ pkgs.coreutils ];
      script = ''
        install -d -m 0750 -o root -g root \
          ${lib.escapeShellArg cfg.stateDir}/library \
          ${lib.escapeShellArg cfg.stateDir}/model-cache
        install -d -m 0700 -o 999 -g 999 \
          ${lib.escapeShellArg cfg.stateDir}/postgres
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
    };

    systemd.services.${pullServiceName} = {
      description = "Pull Immich container images";
      wants = [ "network-online.target" ];
      requires = [
        "opnix-secrets.service"
        "docker.service"
      ];
      after = [
        "opnix-secrets.service"
        "docker.service"
        "network-online.target"
      ];
      unitConfig.ConditionFileNotEmpty = environmentFile;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        EnvironmentFile = environmentFile;
        ExecStartPre = "${pkgs.docker-compose}/bin/docker-compose --project-name immich --file ${composeFile} config --quiet";
        ExecStart = "${pkgs.docker-compose}/bin/docker-compose --project-name immich --file ${composeFile} pull";
        TimeoutStartSec = 1800;
        UMask = "0077";
      };
    };

    systemd.services.${composeServiceName} = {
      description = "Immich photo and video stack";
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
        RuntimeDirectory = "immich";
        RuntimeDirectoryMode = "0700";
        EnvironmentFile = environmentFile;
        ExecStartPre = [
          "${renderConfig}/bin/immich-render-config"
          "${pkgs.docker-compose}/bin/docker-compose --project-name immich --file ${composeFile} config --quiet"
        ];
        ExecStart = "${pkgs.docker-compose}/bin/docker-compose --project-name immich --file ${composeFile} up --detach --wait --wait-timeout 300";
        ExecStop = "${pkgs.docker-compose}/bin/docker-compose --project-name immich --file ${composeFile} down --timeout 120";
        TimeoutStartSec = 360;
        TimeoutStopSec = 180;
        UMask = "0077";
      };
    };

    systemd.services.immich-health-check = {
      description = "Check Immich container and HTTP health";
      after = [ "${composeServiceName}.service" ];
      unitConfig.RequiresMountsFor = cfg.stateDir;
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${healthCheck}/bin/immich-health-check";
      };
    };

    systemd.timers.immich-health-check = {
      description = "Check Immich health every 15 minutes";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*:0/15";
        Persistent = true;
        RandomizedDelaySec = "5m";
      };
    };

    systemd.services.immich-schema-check = {
      description = "Check Immich database schema";
      after = [ "${composeServiceName}.service" ];
      unitConfig.RequiresMountsFor = cfg.stateDir;
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${schemaCheck}/bin/immich-schema-check";
      };
    };

    systemd.timers.immich-schema-check = {
      description = "Check the Immich database schema weekly";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "weekly";
        Persistent = true;
        RandomizedDelaySec = "1h";
      };
    };

    systemd.services.borgmatic = lib.mkIf cfg.backUpData {
      unitConfig.RequiresMountsFor = [ cfg.stateDir ];
      serviceConfig = {
        PrivateDevices = true;
        DevicePolicy = "closed";
        DeviceAllow = [ "/dev/zfs rw" ];
        BindPaths = [ "/dev/zfs" ];
      };
    };

    services.borgmatic.settings.commands = lib.mkIf cfg.backUpData [
      {
        before = "action";
        when = [ "create" ];
        run = [ "${backupPrepare}/bin/immich-backup-prepare" ];
      }
      {
        after = "action";
        when = [ "create" ];
        states = [
          "finish"
          "fail"
        ];
        run = [ "${backupCleanup}/bin/immich-backup-cleanup" ];
      }
      {
        after = "error";
        when = [ "create" ];
        run = [ "${backupCleanup}/bin/immich-backup-cleanup" ];
      }
    ];

    shulker.system.modules.backup.dirs = lib.mkIf cfg.backUpData [ snapshotPath ];

    services.onepassword-secrets.secrets.immichEnv = {
      reference = "op://Shulker/${config.networking.hostName}/Immich/Environment";
      services = [
        pullServiceName
        composeServiceName
      ];
      owner = "root";
      group = "root";
      mode = "0400";
    };
  };
}
