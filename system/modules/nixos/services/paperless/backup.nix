# Create portable database dumps and consistent snapshots for Borgmatic, with failure recovery.
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
  # Publish each PostgreSQL dump only after its archive catalogue is readable; keep the latest fourteen.
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
  # Pause writers, dump PostgreSQL, snapshot the stopped stack, then resume and verify it.
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

    if ! timeout 10 systemctl is-active --quiet "$service"; then
      echo "Paperless must be active before taking its backup snapshot" >&2
      exit 69
    fi

    PAPERLESS_MAINTENANCE_LOCK_HELD=1 \
      ${config.systemd.services.paperless-health-check.serviceConfig.ExecStart}

    # Keep the remapped writable layers during backups. The normal Compose
    # unit still uses down for intentional shutdown and configuration changes.
    components=(webserver database broker tika gotenberg)
    declare -A names=(
      [webserver]=paperless_webserver [database]=paperless_postgres
      [broker]=paperless_broker [tika]=paperless_tika [gotenberg]=paperless_gotenberg
    )
    declare -A ids stop_attempted
    invocation="$(timeout 10 systemctl show --property=InvocationID --value "$service")"
    [[ "$invocation" =~ ^[a-f0-9]{32}$ ]] || exit 69
    fail_backup() { echo "Paperless backup failed: $1" >&2; exit 69; }
    active_invocation() {
      timeout 10 systemctl is-active --quiet "$service" \
        && [ "$(timeout 10 systemctl show --property=InvocationID --value "$service")" = "$invocation" ]
    }
    # Pin both the systemd invocation and container IDs so recovery cannot restart a replacement stack.
    owned_containers() {
      local component identity
      active_invocation || return 1
      for component in "''${components[@]}"; do
        identity="$(timeout 10 docker inspect --format \
          '{{.Id}} {{index .Config.Labels "com.docker.compose.project"}} {{index .Config.Labels "com.docker.compose.service"}}' \
          "''${names[$component]}")" || return 1
        [ "$identity" = "''${ids[$component]} paperless $component" ] || return 1
      done
    }
    for component in "''${components[@]}"; do
      ids[$component]="$(timeout 10 docker inspect --format '{{.Id}}' "''${names[$component]}")"
      [[ "''${ids[$component]}" =~ ^[a-f0-9]{64}$ ]] || fail_backup "invalid container identity"
      [ "$(timeout 10 docker inspect --format '{{.State.Running}}' "''${ids[$component]}")" = true ] \
        || fail_backup "container is not running"
    done
    owned_containers || fail_backup "stack identity changed"
    project_ids="$(timeout 10 docker ps --all --no-trunc --filter label=com.docker.compose.project=paperless --format '{{.ID}}')"
    [ "$(printf '%s\n' "$project_ids" | sort)" = "$(printf '%s\n' "''${ids[@]}" | sort)" ] \
      || fail_backup "unexpected Compose container inventory"

    wait_ready() {
      local component="$1" attempt health
      for ((attempt = 0; attempt < 60; attempt++)); do
        owned_containers || return 1
        [ "$(timeout 10 docker inspect --format '{{.State.Running}}' "''${ids[$component]}")" = true ] \
          || return 1
        case "$component" in
          database|broker|webserver)
            health="$(timeout 10 docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{end}}' \
              "''${ids[$component]}")" || return 1
            case "$health" in healthy) return 0 ;; starting) ;; *) return 1 ;; esac
            ;;
          *) return 0 ;;
        esac
        sleep 5
      done
      return 1
    }
    resume_containers() {
      local component running
      owned_containers || return 1
      for component in database broker tika gotenberg webserver; do
        if [ "''${stop_attempted[$component]:-0}" = 1 ]; then
          owned_containers || return 1
          running="$(timeout 10 docker inspect --format '{{.State.Running}}' "''${ids[$component]}")" || return 1
          case "$running" in
            false) timeout 150 docker start "''${ids[$component]}" >/dev/null || return 1 ;;
            true) ;;
            *) return 1 ;;
          esac
        fi
        # Untouched dependencies can fail during a partial stop too. Never
        # restart the writer unless all dependencies are still ready.
        wait_ready "$component" || return 1
      done
    }
    stop_container() {
      local component="$1" stopped_state
      owned_containers || fail_backup "stack changed before stop"
      # Docker may stop the container even if its CLI returns an error.
      stop_attempted[$component]=1
      timeout 150 docker stop --time 120 "''${ids[$component]}" >/dev/null \
        || fail_backup "container stop failed"
      stopped_state="$(timeout 10 docker inspect --format '{{.State.Running}} {{.State.ExitCode}} {{.State.OOMKilled}}' \
        "''${ids[$component]}")"
      [[ "$stopped_state" =~ ^false[[:space:]]([0-9]+)[[:space:]]false$ ]] \
        && [ "''${BASH_REMATCH[1]}" -ne 137 ] || fail_backup "container did not stop cleanly"
    }

    # The exit trap resumes only the containers this run stopped and discards a failed snapshot.
    snapshot_created=0
    recover() {
      status=$?
      trap - EXIT HUP INT TERM
      if ! resume_containers; then
        echo "Paperless backup recovery incomplete: stack changed or containers did not become healthy" >&2
        status=69
      fi
      if [ "$snapshot_created" -eq 1 ] && [ "$status" -ne 0 ]; then
        if zfs list -H -o name -t snapshot "$snapshot" >/dev/null 2>&1; then
          zfs destroy "$snapshot" || echo "Paperless backup snapshot cleanup failed" >&2
        fi
      fi
      exit "$status"
    }
    trap recover EXIT
    trap 'exit 75' HUP INT TERM

    stop_container webserver
    PAPERLESS_MAINTENANCE_LOCK_HELD=1 \
      timeout --kill-after=30 900 ${logicalBackup}/bin/paperless-logical-backup
    for component in tika gotenberg broker database; do
      stop_container "$component"
    done
    owned_containers || fail_backup "stack changed before snapshot"
    for component in "''${components[@]}"; do
      [ "$(timeout 10 docker inspect --format '{{.State.Running}}' "''${ids[$component]}")" = false ] \
        || fail_backup "container resumed before snapshot"
    done
    snapshot_created=1
    zfs snapshot "$snapshot"

    if [ "''${PAPERLESS_BACKUP_TEST_FAIL_AFTER_SNAPSHOT:-0}" = 1 ]; then
      echo "Injecting the requested Paperless post-snapshot backup failure" >&2
      exit 75
    fi

    resume_containers || fail_backup "container resume failed"
    owned_containers || fail_backup "stack changed after resume"
    PAPERLESS_MAINTENANCE_LOCK_HELD=1 \
      ${config.systemd.services.paperless-health-check.serviceConfig.ExecStart}

    trap - EXIT HUP INT TERM
  '';
  backupPrepare = pkgs.writeShellApplication {
    name = "paperless-backup-prepare";
    runtimeInputs = [
      config.boot.zfs.package
      config.virtualisation.docker.package
      pkgs.coreutils
      pkgs.systemd
      pkgs.util-linux
      logicalBackup
    ];
    text = backupPrepareScript;
  };
  # Remove only the reserved snapshot after Borgmatic finishes or fails.
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
  # Refresh the portable document export and record the exact version required for import.
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

    # Grant the backup hooks access to ZFS inside Borgmatic's restricted service environment.
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

    # Borg reads the immutable snapshot while the live service is already running again.
    shulker.system.modules.backup.dirs = lib.mkIf cfg.backUpData [ snapshotPath ];
  };
}
