{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.shulker.system.modules.paperless;
  composeServiceName = "paperless-compose";
  snapshot = "${cfg.dataset}@${cfg.backupSnapshotName}";
  snapshotPath = "${cfg.stateDir}/.zfs/snapshot/${cfg.backupSnapshotName}";
  maintenanceLock = "/run/lock/paperless-maintenance.lock";
  logicalBackupScript = ''
    readonly dumps_dir=${lib.escapeShellArg "${cfg.stateDir}/dumps"}

    if [ "''${PAPERLESS_MAINTENANCE_LOCK_HELD:-0}" != 1 ]; then
      exec 9>${maintenanceLock}
      flock 9
    fi

    if ! systemctl is-active --quiet ${composeServiceName}.service; then
      echo "Paperless must be active before creating a logical database dump" >&2
      exit 69
    fi
    if [ "$(docker inspect --format '{{.State.Running}}' paperless_postgres)" != true ]; then
      echo "Paperless PostgreSQL container is not running" >&2
      exit 69
    fi

    temporary_dump="$(mktemp "$dumps_dir/.paperless-dump.XXXXXXXXXX")"
    cleanup_temporary_dump() {
      rm -f -- "$temporary_dump"
    }
    trap cleanup_temporary_dump EXIT
    trap 'exit 1' INT TERM

    docker exec paperless_postgres pg_dump \
      --username paperless \
      --dbname paperless \
      --format custom >"$temporary_dump"
    docker exec --interactive paperless_postgres pg_restore --list \
      <"$temporary_dump" >/dev/null

    chmod 0600 "$temporary_dump"
    completed_dump="$dumps_dir/paperless-$(date --utc +%Y%m%dT%H%M%S.%NZ).dump"
    mv -- "$temporary_dump" "$completed_dump"
    trap - EXIT INT TERM

    mapfile -d "" -t dumps < <(
      find "$dumps_dir" -maxdepth 1 -type f -name 'paperless-*.dump' \
        -printf '%T@ %p\0' | sort --zero-terminated --numeric-sort --reverse
    )
    for ((index = 14; index < ''${#dumps[@]}; index++)); do
      dump_path="''${dumps[$index]#* }"
      case "$dump_path" in
        "$dumps_dir"/paperless-*.dump) rm -f -- "$dump_path" ;;
        *)
          echo "Refusing unexpected Paperless logical dump path" >&2
          exit 65
          ;;
      esac
    done

    echo "Created and validated a Paperless PostgreSQL logical dump"
  '';
  logicalBackup = pkgs.writeShellApplication {
    name = "paperless-logical-backup";
    runtimeInputs = [
      config.virtualisation.docker.package
      pkgs.coreutils
      pkgs.findutils
      pkgs.systemd
      pkgs.util-linux
    ];
    text = logicalBackupScript;
  };
  backupPrepareScript = ''
    readonly dataset=${lib.escapeShellArg cfg.dataset}
    readonly snapshot_name=${lib.escapeShellArg cfg.backupSnapshotName}
    readonly snapshot=${lib.escapeShellArg snapshot}
    readonly service=${lib.escapeShellArg "${composeServiceName}.service"}

    if [ "$snapshot_name" != borgmatic ] || [ "$snapshot" != "$dataset@$snapshot_name" ]; then
      echo "Refusing unexpected Paperless snapshot target" >&2
      exit 64
    fi

    exec 9>${maintenanceLock}
    flock 9

    if zfs list -H -o name -t snapshot "$snapshot" >/dev/null 2>&1; then
      zfs destroy "$snapshot"
    fi

    if ! systemctl is-active --quiet "$service"; then
      echo "Paperless must be active before taking its backup snapshot" >&2
      exit 69
    fi

    PAPERLESS_MAINTENANCE_LOCK_HELD=1 \
      ${config.systemd.services.paperless-health-check.serviceConfig.ExecStart}
    PAPERLESS_MAINTENANCE_LOCK_HELD=1 \
      ${logicalBackup}/bin/paperless-logical-backup

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

    if [ "''${PAPERLESS_BACKUP_TEST_FAIL_AFTER_SNAPSHOT:-0}" = 1 ]; then
      echo "Injecting the requested Paperless post-snapshot backup failure" >&2
      exit 75
    fi

    systemctl start "$service"
    systemctl is-active --quiet "$service"
    PAPERLESS_MAINTENANCE_LOCK_HELD=1 \
      ${config.systemd.services.paperless-health-check.serviceConfig.ExecStart}
    service_stopped=0

    trap - EXIT INT TERM
  '';
  backupPrepare = pkgs.writeShellApplication {
    name = "paperless-backup-prepare";
    runtimeInputs = [
      config.boot.zfs.package
      pkgs.coreutils
      pkgs.systemd
      pkgs.util-linux
      logicalBackup
    ];
    text = backupPrepareScript;
  };
  backupCleanupScript = ''
    readonly dataset=${lib.escapeShellArg cfg.dataset}
    readonly snapshot_name=${lib.escapeShellArg cfg.backupSnapshotName}
    readonly snapshot=${lib.escapeShellArg snapshot}

    if [ "$snapshot_name" != borgmatic ] || [ "$snapshot" != "$dataset@$snapshot_name" ]; then
      echo "Refusing unexpected Paperless snapshot cleanup target" >&2
      exit 64
    fi

    exec 9>${maintenanceLock}
    flock 9

    if zfs list -H -o name -t snapshot "$snapshot" >/dev/null 2>&1; then
      zfs destroy "$snapshot"
    fi
  '';
  backupCleanup = pkgs.writeShellApplication {
    name = "paperless-backup-cleanup";
    runtimeInputs = [
      config.boot.zfs.package
      pkgs.util-linux
    ];
    text = backupCleanupScript;
  };
  preUpgradeExport = pkgs.writeShellApplication {
    name = "paperless-pre-upgrade-export";
    runtimeInputs = [
      config.virtualisation.docker.package
      pkgs.coreutils
      pkgs.systemd
      pkgs.util-linux
    ];
    text = ''
      readonly state_dir=${lib.escapeShellArg cfg.stateDir}
      readonly export_dir="$state_dir/export"
      readonly current_export="$export_dir/current"

      if [ "$export_dir" != ${lib.escapeShellArg "${cfg.stateDir}/export"} ]; then
        echo "Refusing unexpected Paperless export path" >&2
        exit 64
      fi

      exec 9>${maintenanceLock}
      flock 9

      if ! systemctl is-active --quiet ${composeServiceName}.service; then
        echo "Paperless must be active before creating a portable export" >&2
        exit 69
      fi
      PAPERLESS_MAINTENANCE_LOCK_HELD=1 \
        ${config.systemd.services.paperless-health-check.serviceConfig.ExecStart}

      install -d -m 0750 -o ${toString cfg.uid} -g ${toString cfg.gid} "$current_export"
      docker exec paperless_webserver document_exporter \
        /usr/src/paperless/export/current \
        --delete \
        --compare-checksums \
        --compare-json \
        --no-progress-bar

      {
        printf 'paperless_version=%s\n' ${lib.escapeShellArg cfg.version}
        printf 'completed_at=%s\n' "$(date --utc --iso-8601=seconds)"
        printf '%s\n' 'API tokens are not included and must be regenerated after import.'
        printf '%s\n' 'Import requires this exact Paperless version.'
      } >"$current_export/paperless-version.txt"
      chmod 0640 "$current_export/paperless-version.txt"
      chown ${toString cfg.uid}:${toString cfg.gid} "$current_export/paperless-version.txt"

      echo "Paperless ${cfg.version} portable export completed"
    '';
  };
in
{
  options.shulker.system.modules.paperless = {
    logicalBackupScript = lib.mkOption {
      type = lib.types.lines;
      readOnly = true;
      internal = true;
      description = "Logical backup source exposed for evaluation contracts.";
    };

    backupPrepareScript = lib.mkOption {
      type = lib.types.lines;
      readOnly = true;
      internal = true;
      description = "Snapshot preparation source exposed for evaluation contracts.";
    };

    backupCleanupScript = lib.mkOption {
      type = lib.types.lines;
      readOnly = true;
      internal = true;
      description = "Snapshot cleanup source exposed for evaluation contracts.";
    };
  };

  config = lib.mkIf cfg.enable {
    shulker.system.modules.paperless = {
      inherit
        backupCleanupScript
        backupPrepareScript
        logicalBackupScript
        ;
    };

    environment.systemPackages = [
      backupCleanup
      backupPrepare
      logicalBackup
      preUpgradeExport
    ];

    systemd.services.paperless-logical-backup = {
      description = "Create a validated Paperless PostgreSQL logical dump";
      requires = [ "${composeServiceName}.service" ];
      after = [ "${composeServiceName}.service" ];
      unitConfig.RequiresMountsFor = cfg.stateDir;
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${logicalBackup}/bin/paperless-logical-backup";
      };
    };

    systemd.timers.paperless-logical-backup = {
      description = "Create a daily Paperless PostgreSQL logical dump";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
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
        CapabilityBoundingSet = [
          "CAP_DAC_READ_SEARCH"
          "CAP_NET_RAW"
          "CAP_SYS_ADMIN"
        ];
      };
    };

    services.borgmatic.settings.commands = lib.mkIf cfg.backUpData [
      {
        before = "action";
        when = [ "create" ];
        run = [ "${backupPrepare}/bin/paperless-backup-prepare" ];
      }
      {
        after = "action";
        when = [ "create" ];
        states = [
          "finish"
          "fail"
        ];
        run = [ "${backupCleanup}/bin/paperless-backup-cleanup" ];
      }
      {
        after = "error";
        when = [ "create" ];
        run = [ "${backupCleanup}/bin/paperless-backup-cleanup" ];
      }
    ];

    shulker.system.modules.backup.dirs = lib.mkIf cfg.backUpData [ snapshotPath ];
  };
}
