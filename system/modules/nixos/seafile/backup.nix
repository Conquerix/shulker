{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.shulker.system.modules.seafile;
  maintenanceLock = "/run/lock/seafile-maintenance.lock";
  backupRuntimeDir = "/run/seafile-backup";
  validatorStateDir = "${cfg.stateDir}/control/backup-validator";
  snapshotPath = "${cfg.stateDir}/.zfs/snapshot/${cfg.backupSnapshotName}";
  restoreProxyImage = "docker.io/library/nginx:alpine@sha256:4a73073bd557c65b759505da037898b61f1be6cbcc3c2c3aeac22d2a470c1752";
  composeFactory = import ../../../../lib/seafile-compose.nix { inherit pkgs; };
  restoreBase = composeFactory {
    projectName = "seafile-restore";
    containerNames = {
      seafile = "seafile-restore-seafile";
      database = "seafile-restore-mariadb";
      redis = "seafile-restore-redis";
      seasearch = "seafile-restore-seasearch";
      notification = "seafile-restore-notification";
      metadata = "seafile-restore-metadata";
      onlyoffice = "seafile-restore-onlyoffice";
    };
    networkName = "seafile-restore-net";
    stateDir = "\${SEAFILE_RESTORE_TARGET:?}";
    appRuntimeDir = "\${SEAFILE_RESTORE_RUNTIME:?}/app";
    metadataRuntimeDir = "\${SEAFILE_RESTORE_RUNTIME:?}/metadata";
    bindAddress = "127.0.0.1";
    ports = {
      seafile = 24239;
      onlyoffice = 24240;
      notification = 24241;
    };
    urls = {
      hostname = "files.restore.invalid:24239";
      notificationInternal = "http://seafile-restore-notification:8083";
      notificationPublic = "https://files.restore.invalid:24241/notification";
    };
    images = {
      seafile = cfg.seafileImage;
      database = cfg.databaseImage;
      redis = cfg.redisImage;
      seasearch = cfg.seasearchImage;
      notification = cfg.notificationImage;
      metadata = cfg.metadataImage;
      onlyoffice = cfg.onlyOfficeImage;
    };
    metadata = {
      fileCountLimit = cfg.metadataFileCountLimit;
      cacheSize = cfg.metadataCacheSize;
      checkUpdateInterval = cfg.metadataCheckUpdateInterval;
    };
    publishApplicationPorts = false;
    seafileExtraVolumes = [
      "\${SEAFILE_RESTORE_RUNTIME:?}/ca/ca.crt:/usr/local/share/ca-certificates/seafile-restore-ca.crt:ro"
    ];
    onlyOfficeExtraVolumes = [
      "\${SEAFILE_RESTORE_RUNTIME:?}/ca/ca.crt:/usr/local/share/ca-certificates/seafile-restore-ca.crt:ro"
    ];
  };
  restoreComposeConfig = lib.recursiveUpdate restoreBase.composeConfig {
    services.proxy = {
      container_name = "seafile-restore-proxy";
      image = restoreProxyImage;
      restart = "no";
      environment = {
        RESTORE_FILES_URL = "https://files.restore.invalid:24239";
        RESTORE_ONLYOFFICE_URL = "https://office.restore.invalid:24240";
        RESTORE_NOTIFICATION_URL = "https://files.restore.invalid:24241/notification";
      };
      networks."seafile-restore-net".aliases = [
        "files.restore.invalid"
        "office.restore.invalid"
      ];
      ports = [
        "127.0.0.1:24239:443/tcp"
        "127.0.0.1:24240:444/tcp"
        "127.0.0.1:24241:445/tcp"
      ];
      volumes = [
        {
          type = "bind";
          source = "\${SEAFILE_RESTORE_RUNTIME:?}/proxy/nginx.conf";
          target = "/etc/nginx/nginx.conf";
          read_only = true;
          bind.create_host_path = false;
        }
        {
          type = "bind";
          source = "\${SEAFILE_RESTORE_RUNTIME:?}/ca";
          target = "/run/seafile-restore-ca";
          read_only = true;
          bind.create_host_path = false;
        }
      ];
    };
  };
  restoreComposeFile =
    (pkgs.formats.yaml { }).generate "seafile-restore-compose.yml"
      restoreComposeConfig;

  commonScript = ''
    systemctl_command="''${SEAFILE_SYSTEMCTL_COMMAND:-systemctl}"
    docker_command="''${SEAFILE_DOCKER_COMMAND:-docker}"
    zfs_command="''${SEAFILE_ZFS_COMMAND:-zfs}"
    timeout_command="''${SEAFILE_TIMEOUT_COMMAND:-timeout}"
    install_command="''${SEAFILE_INSTALL_COMMAND:-install}"
    state_dir="''${SEAFILE_STATE_DIR:-${cfg.stateDir}}"
    dataset="''${SEAFILE_DATASET:-${cfg.dataset}}"
    snapshot_name="''${SEAFILE_SNAPSHOT_NAME:-${cfg.backupSnapshotName}}"
    snapshot="$dataset@$snapshot_name"
    snapshot_path="$state_dir/.zfs/snapshot/$snapshot_name"
    runtime_dir="''${SEAFILE_BACKUP_RUNTIME_DIR:-${backupRuntimeDir}}"
    validator_state_dir="''${SEAFILE_VALIDATOR_STATE_DIR:-${validatorStateDir}}"
    lock_file="''${SEAFILE_MAINTENANCE_LOCK:-${maintenanceLock}}"
    owner_marker="$state_dir/control/backup-snapshot-owner"
    cleanup_token="$runtime_dir/cleanup-armed"
    : "$systemctl_command" "$docker_command" "$zfs_command" "$timeout_command" "$install_command" \
      "$state_dir" "$dataset" "$snapshot_name" "$snapshot" "$snapshot_path" \
      "$runtime_dir" "$validator_state_dir" "$lock_file" "$owner_marker" "$cleanup_token"

    fail_backup() { echo "Seafile backup failed: $1" >&2; exit 69; }
    path_present() { [ -e "$1" ] || [ -L "$1" ]; }
    snapshot_exists() { "$zfs_command" list -H -o name -t snapshot "$snapshot" >/dev/null 2>&1; }
    snapshot_guid() { "$zfs_command" get -H -o value guid "$snapshot"; }

    marker_field() {
      local file="$1" key="$2" value count
      [ -f "$file" ] && [ ! -L "$file" ] || return 1
      count="$(grep -c "^$key=" "$file" || true)"
      [ "$count" -eq 1 ] || return 1
      value="$(sed -n "s/^$key=//p" "$file")"
      [ -n "$value" ] || return 1
      printf '%s\n' "$value"
    }

    write_protected_file() {
      local destination="$1" content="$2" directory temporary
      directory="''${destination%/*}"
      "$install_command" -d -m 0700 -o 0 -g 0 "$directory"
      temporary="$(mktemp "$directory/.''${destination##*/}.XXXXXXXXXX")"
      chmod 0600 "$temporary"
      if [ "''${SEAFILE_TEST_SKIP_OWNERSHIP:-0}" != 1 ]; then chown 0:0 "$temporary"; fi
      printf '%s\n' "$content" >"$temporary"
      sync -f "$temporary"
      mv -- "$temporary" "$destination"
      sync -f "$directory"
    }

    prove_inherited_lock() {
      local fd_path fd_identity lock_identity
      [ "''${SEAFILE_TEST_SKIP_LOCK_PROOF:-0}" != 1 ] || return 0
      if [ -e /proc/self/fd/9 ]; then
        fd_path=/proc/self/fd/9
        fd_identity="$(stat --dereference --format '%d:%i' -- "$fd_path")" || return 1
        lock_identity="$(stat --format '%d:%i' -- "$lock_file")" || return 1
      elif [ -e /dev/fd/9 ]; then
        fd_path=/dev/fd/9
        fd_identity="$(stat --dereference --format '%i' -- "$fd_path")" || return 1
        lock_identity="$(stat --format '%i' -- "$lock_file")" || return 1
      else
        return 1
      fi
      [ "$fd_identity" = "$lock_identity" ] || return 1
      exec 8>"$lock_file"
      if flock -n 8; then
        flock -u 8
        exec 8>&-
        return 1
      fi
      exec 8>&-
      flock -n 9
    }

    validate_snapshot_constants() {
      [ "$snapshot_name" = borgmatic ] || fail_backup "unexpected snapshot name"
      [ "$snapshot" = "$dataset@borgmatic" ] || fail_backup "unexpected snapshot target"
      [ "$dataset" = "${cfg.dataset}" ] || fail_backup "unexpected dataset"
    }
  '';

  logicalBackupScript = ''
    ${commonScript}
    [ "''${SEAFILE_MAINTENANCE_LOCK_HELD:-0}" = 1 ] \
      || fail_backup "logical backup requires the held-lock flag"
    prove_inherited_lock || fail_backup "logical backup requires the inherited held lock descriptor"
    candidate_file="''${SEAFILE_BACKUP_CANDIDATE_FILE:-$runtime_dir/current-dump}"
    invocation="''${SEAFILE_BACKUP_INVOCATION:-}"
    [[ "$invocation" =~ ^[a-zA-Z0-9-]+$ ]] || fail_backup "invalid logical backup invocation"
    environment_file="''${SEAFILE_ENVIRONMENT_FILE:-/run/seafile-host/environment}"
    writers=(seafile-onlyoffice seafile-notification seafile-metadata seafile-seasearch seafile seafile-redis)
    for writer in "''${writers[@]}"; do
      [ "$("$docker_command" inspect --format '{{.State.Running}}' "$writer" 2>/dev/null)" = false ] \
        || fail_backup "application writer remains running"
    done
    [ "$("$docker_command" inspect --format '{{.State.Running}}' seafile-mariadb)" = true ] \
      || fail_backup "MariaDB is not running for logical dumps"
    [ -f "$environment_file" ] && [ ! -L "$environment_file" ] \
      || fail_backup "protected runtime environment is unavailable"
    set -a
    # Generated by the strict allow-listed Seafile parser; values contain no shell syntax.
    # shellcheck disable=SC1090
    . "$environment_file"
    set +a
    MYSQL_PWD="''${SEAFILE_MYSQL_DB_PASSWORD:?}"
    export MYSQL_PWD
    unset SEAFILE_MYSQL_DB_PASSWORD INIT_SEAFILE_ADMIN_PASSWORD INIT_SEAFILE_MYSQL_ROOT_PASSWORD

    backups_dir="$state_dir/backups"
    temporary="$backups_dir/.seafile-dump-$invocation"
    final="$backups_dir/seafile-$(date --utc +%Y%m%dT%H%M%S)-$invocation"
    [ ! -e "$temporary" ] && [ ! -e "$final" ] || fail_backup "logical backup candidate collision"
    "$install_command" -d -m 0700 -o 0 -g 0 "$temporary"
    cleanup_candidate() {
      status=$?
      trap - EXIT
      if [ "$status" -ne 0 ]; then
        case "$temporary" in "$backups_dir"/.seafile-dump-*) rm -rf -- "$temporary" ;; esac
      fi
      unset MYSQL_PWD
      exit "$status"
    }
    trap cleanup_candidate EXIT
    trap 'exit 75' HUP INT TERM

    databases=(ccnet_db seafile_db seahub_db)
    pids=()
    for database in "''${databases[@]}"; do
      (
        "$timeout_command" 1800 "$docker_command" exec --env MYSQL_PWD seafile-mariadb \
          mariadb-dump --user seafile --single-transaction --quick --hex-blob \
          --routines --events --triggers --databases "$database" >"$temporary/$database.sql"
      ) &
      pids+=("$!")
    done
    failed=0
    for pid in "''${pids[@]}"; do wait "$pid" || failed=1; done
    [ "$failed" -eq 0 ] || fail_backup "parallel MariaDB dump failed or timed out"

    manifest_databases='[]'
    for database in "''${databases[@]}"; do
      dump="$temporary/$database.sql"
      [ -s "$dump" ] || fail_backup "$database dump is empty"
      "$timeout_command" 300 grep -Eq '^(CREATE TABLE|INSERT INTO|-- Database:)' "$dump" \
        || fail_backup "$database dump is structurally incomplete"
      size="$(stat --format '%s' "$dump")"
      checksum="$(sha256sum "$dump" | cut -d' ' -f1)"
      manifest_databases="$(jq -c --arg name "$database" --arg file "$database.sql" \
        --argjson size "$size" --arg checksum "$checksum" \
        '. + [{name:$name,file:$file,size_bytes:$size,sha256:$checksum}]' \
        <<<"$manifest_databases")"
      chmod 0600 "$dump"
    done
    jq -nS --argjson release_versions ${lib.escapeShellArg (builtins.toJSON cfg.releaseVersions)} \
      --arg completed_at "$(date --utc --iso-8601=seconds)" \
      --arg schema_format mariadb-sql-v1 --arg transaction_kind writers_quiesced=true \
      --argjson databases "$manifest_databases" \
      '{release_versions:$release_versions,completed_at:$completed_at,databases:$databases,schema_format:$schema_format,transaction_kind:$transaction_kind}' \
      >"$temporary/manifest.json"
    chmod 0600 "$temporary/manifest.json"
    sync -f "$temporary"
    mv -- "$temporary" "$final"
    sync -f "$backups_dir"
    write_protected_file "$candidate_file" "$final"
    unset MYSQL_PWD
    trap - EXIT HUP INT TERM
  '';

  validateLogicalBackupScript = ''
    ${commonScript}
    [ "''${SEAFILE_MAINTENANCE_LOCK_HELD:-0}" = 1 ] \
      || fail_backup "logical validation requires the held-lock flag"
    prove_inherited_lock || fail_backup "logical validation requires the inherited held lock descriptor"
    invocation="''${SEAFILE_BACKUP_INVOCATION:-}"
    candidate_file="''${SEAFILE_BACKUP_CANDIDATE_FILE:-$runtime_dir/current-dump}"
    [[ "$invocation" =~ ^[a-zA-Z0-9-]+$ ]] || fail_backup "invalid validator invocation"
    [ -f "$candidate_file" ] && [ ! -L "$candidate_file" ] || fail_backup "candidate handoff is missing"
    live_candidate="$(cat "$candidate_file")"
    case "$live_candidate" in "$state_dir"/backups/seafile-*-$invocation) ;; *) fail_backup "candidate handoff is foreign" ;; esac
    candidate_name="''${live_candidate##*/}"
    candidate="$snapshot_path/backups/$candidate_name"
    [ -d "$candidate" ] && [ ! -L "$candidate" ] || fail_backup "snapshot candidate is missing"
    [ "$(stat --format '%u:%g:%a' "$live_candidate")" = 0:0:700 ] \
      || fail_backup "live candidate ownership is foreign"
    jq -e '.transaction_kind == "writers_quiesced=true" and (.databases | length == 3)' \
      "$candidate/manifest.json" >/dev/null || fail_backup "candidate manifest is invalid"

    total_size=0
    for dump in ccnet_db.sql seafile_db.sql seahub_db.sql; do
      [ -s "$candidate/$dump" ] || fail_backup "snapshot dump is missing"
      total_size="$((total_size + $(stat --format '%s' "$candidate/$dump")))"
    done
    "$install_command" -d -m 0700 -o 0 -g 0 "$validator_state_dir"
    required_bytes="$((total_size * 6 + 1073741824))"
    available_bytes="$(( $(df --output=avail -B1 "$validator_state_dir" | tail -1) ))"
    available_inodes="$(( $(df --output=iavail "$validator_state_dir" | tail -1) ))"
    [ "$available_bytes" -ge "$required_bytes" ] || fail_backup "validator filesystem has insufficient bytes"
    [ "$available_inodes" -ge 10000 ] || fail_backup "validator filesystem has insufficient inodes"

    workspace="$validator_state_dir/$invocation"
    [ ! -e "$workspace" ] || fail_backup "validator workspace collision"
    "$install_command" -d -m 0700 -o 0 -g 0 "$workspace"
    credential="$workspace/environment"
    cidfile="$workspace/container.cid"
    validator_name="seafile-backup-validator-$invocation"
    if "$docker_command" inspect "$validator_name" >/dev/null 2>&1; then fail_backup "validator name collision"; fi
    validator_password="$(openssl rand -hex 32)"
    printf 'MARIADB_ROOT_PASSWORD=%s\n' "$validator_password" >"$credential"
    chmod 0600 "$credential"
    MYSQL_PWD="$validator_password"
    export MYSQL_PWD
    cleanup_validator() {
      status=$?
      trap - EXIT
      if [ -f "$cidfile" ]; then
        validator_id="$(cat "$cidfile")"
        if [ -n "$validator_id" ] \
          && [ "$("$docker_command" inspect --format '{{index .Config.Labels "shulker.seafile.backup-invocation"}}' "$validator_id" 2>/dev/null)" = "$invocation" ]; then
          "$docker_command" rm -f "$validator_id" >/dev/null 2>&1 || true
        fi
      fi
      rm -f -- "$credential" "$cidfile"
      if [ "$workspace" = "$validator_state_dir/$invocation" ]; then rm -rf -- "$workspace"; fi
      if [ "$status" -ne 0 ] && [ -d "$live_candidate" ] \
        && [ "$(stat --format '%u:%g:%a' "$live_candidate")" = 0:0:700 ]; then
        case "$live_candidate" in "$state_dir"/backups/seafile-*-$invocation) rm -rf -- "$live_candidate" ;; esac
      fi
      unset MYSQL_PWD validator_password
      exit "$status"
    }
    trap cleanup_validator EXIT
    trap 'exit 75' HUP INT TERM

    "$docker_command" run --detach --name "$validator_name" \
      --label "shulker.seafile.backup-invocation=$invocation" --cidfile "$cidfile" \
      --env-file "$credential" --network none --publish-all=false \
      --volume "$workspace:/var/lib/mysql" ${lib.escapeShellArg cfg.databaseImage} >/dev/null
    validator_id="$(cat "$cidfile")"
    for _ in $(seq 1 180); do
      "$docker_command" exec --env MYSQL_PWD "$validator_id" mariadb-admin --user root ping >/dev/null 2>&1 && break
      sleep 1
    done
    "$docker_command" exec --env MYSQL_PWD "$validator_id" mariadb-admin --user root ping >/dev/null
    for database in ccnet_db seafile_db seahub_db; do
      "$timeout_command" 3600 "$docker_command" exec -i --env MYSQL_PWD "$validator_id" \
        mariadb --user root <"$candidate/$database.sql"
      count="$("$docker_command" exec --env MYSQL_PWD "$validator_id" mariadb -N --user root \
        -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$database';")"
      [ "$count" -gt 0 ] || fail_backup "$database import has no schema objects"
    done
    validation_marker="$state_dir/control/$candidate_name.validated"
    validation_content="$(printf 'invocation=%s\ncandidate=%s\nvalidated_at=%s\ntransaction_kind=writers_quiesced=true\n' \
      "$invocation" "$live_candidate" "$(date --utc --iso-8601=seconds)")"
    write_protected_file "$validation_marker" "$validation_content"
    mapfile -d $'\0' -t markers < <(find "$state_dir/control" -maxdepth 1 -type f \
      -name 'seafile-*.validated' -printf '%T@ %p\0' | sort -zrn)
    for ((index = ${toString cfg.logicalDumpRetention}; index < ''${#markers[@]}; index++)); do
      old_marker="''${markers[$index]#* }"
      old_candidate="$(marker_field "$old_marker" candidate || true)"
      case "$old_candidate" in "$state_dir"/backups/seafile-*) rm -rf -- "$old_candidate"; rm -f -- "$old_marker" ;; esac
    done
    trap - EXIT HUP INT TERM
    "$docker_command" rm -f "$validator_id" >/dev/null
    rm -rf -- "$workspace"
    unset MYSQL_PWD validator_password
  '';

  backupPrepareScript = ''
    ${commonScript}
    validate_snapshot_constants
    health_command="''${SEAFILE_HEALTH_COMMAND:-${config.systemd.services.seafile-health-check.serviceConfig.ExecStart}}"
    logical_command="''${SEAFILE_LOGICAL_BACKUP_COMMAND:-seafile-logical-backup}"
    validate_logical_command="''${SEAFILE_VALIDATE_LOGICAL_BACKUP_COMMAND:-seafile-validate-logical-backup}"
    validate_state_command="''${SEAFILE_VALIDATE_STATE_COMMAND:-${lib.getExe cfg.validateStatePackage}}"
    "$install_command" -d -m 0700 -o 0 -g 0 "$runtime_dir"
    exec 9>"$lock_file"
    flock 9
    rm -f -- "$cleanup_token"
    "$validate_state_command"
    "$systemctl_command" is-active --quiet seafile-compose.service || fail_backup "Seafile stack is inactive"
    SEAFILE_MAINTENANCE_LOCK_HELD=1 "$health_command" || fail_backup "Seafile stack is unhealthy"
    if snapshot_exists || path_present "$owner_marker"; then fail_backup "reserved snapshot or ownership marker already exists"; fi

    invocation="$(uuidgen | tr '[:upper:]' '[:lower:]')"
    [[ "$invocation" =~ ^[a-f0-9-]+$ ]] || fail_backup "invalid generated invocation"
    candidate_file="$runtime_dir/current-dump"
    onlyoffice_prepare_attempted=0
    onlyoffice_original=0
    snapshot_created=0
    marker_written=0
    stopped=()
    all_containers=(seafile-mariadb seafile-redis seafile seafile-seasearch seafile-notification seafile-metadata seafile-onlyoffice)
    for container in "''${all_containers[@]}"; do
      [ "$("$docker_command" inspect --format '{{.State.Running}}' "$container")" = true ] \
        || fail_backup "$container is not running"
    done
    onlyoffice_original=1

    restart_owned() {
      local container seen=0
      for container in "''${stopped[@]}"; do
        "$docker_command" start "$container" >/dev/null 2>&1 || true
        [ "$container" = seafile-onlyoffice ] && seen=1
      done
      if [ "$onlyoffice_prepare_attempted" -eq 1 ] && [ "$onlyoffice_original" -eq 1 ] && [ "$seen" -eq 0 ]; then
        "$docker_command" start seafile-onlyoffice >/dev/null 2>&1 || true
      fi
    }

    destroy_current_snapshot() {
      [ "$snapshot_created" -eq 1 ] && [ "$marker_written" -eq 1 ] || return 0
      snapshot_exists || return 0
      marker_invocation="$(marker_field "$owner_marker" invocation || true)"
      marker_dataset="$(marker_field "$owner_marker" dataset || true)"
      marker_snapshot="$(marker_field "$owner_marker" snapshot || true)"
      marker_guid="$(marker_field "$owner_marker" guid || true)"
      live_guid="$(snapshot_guid || true)"
      if [ "$marker_invocation" = "$invocation" ] && [ "$marker_dataset" = "$dataset" ] \
        && [ "$marker_snapshot" = "$snapshot" ] && [ "$marker_guid" = "$live_guid" ]; then
        if "$zfs_command" destroy "$snapshot"; then
          rm -f -- "$owner_marker" "$cleanup_token" "$state_dir/control/"*"-$invocation.validated"
          sync -f "$state_dir/control"
        fi
      fi
    }

    recover_prepare() {
      status=$?
      trap - EXIT
      restart_owned
      [ "$status" -eq 0 ] || destroy_current_snapshot
      exit "$status"
    }
    trap recover_prepare EXIT
    trap 'exit 75' HUP INT TERM

    onlyoffice_prepare_attempted=1
    "$timeout_command" 330 "$docker_command" exec seafile-onlyoffice documentserver-prepare4shutdown.sh
    stop_gracefully() {
      local container="$1"
      "$docker_command" kill --signal TERM "$container" >/dev/null
      stopped+=("$container")
      [ "''${SEAFILE_TEST_NO_SLEEP:-0}" != 1 ] || return 0
      for _ in $(seq 1 120); do
        [ "$("$docker_command" inspect --format '{{.State.Running}}' "$container" 2>/dev/null)" = false ] && return 0
        sleep 1
      done
      fail_backup "$container did not stop after TERM; refusing SIGKILL"
    }
    for container in seafile-onlyoffice seafile-notification seafile-metadata seafile-seasearch seafile seafile-redis; do
      stop_gracefully "$container"
    done
    SEAFILE_MAINTENANCE_LOCK_HELD=1 SEAFILE_BACKUP_INVOCATION="$invocation" \
      SEAFILE_BACKUP_CANDIDATE_FILE="$candidate_file" "$timeout_command" 2700 "$logical_command"
    stop_gracefully seafile-mariadb
    "$zfs_command" snapshot "$snapshot"
    snapshot_created=1
    guid="$(snapshot_guid)"
    [[ "$guid" =~ ^[0-9]+$ ]] || fail_backup "snapshot GUID is invalid"
    owner_content="$(printf 'invocation=%s\ndataset=%s\nsnapshot=%s\nguid=%s\ncreated_at=%s\n' \
      "$invocation" "$dataset" "$snapshot" "$guid" "$(date --utc --iso-8601=seconds)")"
    write_protected_file "$owner_marker" "$owner_content"
    marker_written=1
    restart_owned
    stopped=()
    SEAFILE_MAINTENANCE_LOCK_HELD=1 "$health_command"
    SEAFILE_MAINTENANCE_LOCK_HELD=1 SEAFILE_BACKUP_INVOCATION="$invocation" \
      SEAFILE_BACKUP_CANDIDATE_FILE="$candidate_file" "$timeout_command" 14400 "$validate_logical_command"
    token_content="$(printf 'invocation=%s\nguid=%s\n' "$invocation" "$guid")"
    write_protected_file "$cleanup_token" "$token_content"
    trap - EXIT HUP INT TERM
  '';

  backupCleanupScript = ''
    ${commonScript}
    validate_snapshot_constants
    "$install_command" -d -m 0700 -o 0 -g 0 "$runtime_dir"
    exec 9>"$lock_file"
    flock 9
    marker_present=0 token_present=0 snapshot_present=0
    path_present "$owner_marker" && marker_present=1
    path_present "$cleanup_token" && token_present=1
    snapshot_exists && snapshot_present=1
    [ "$marker_present$token_present$snapshot_present" != 000 ] || exit 0
    [ "$marker_present$token_present$snapshot_present" = 111 ] || fail_backup "snapshot cleanup ownership state is incomplete"
    invocation="$(marker_field "$owner_marker" invocation || true)"
    marker_dataset="$(marker_field "$owner_marker" dataset || true)"
    marker_snapshot="$(marker_field "$owner_marker" snapshot || true)"
    marker_guid="$(marker_field "$owner_marker" guid || true)"
    token_invocation="$(marker_field "$cleanup_token" invocation || true)"
    token_guid="$(marker_field "$cleanup_token" guid || true)"
    live_guid="$(snapshot_guid || true)"
    [ -n "$invocation" ] && [ "$invocation" = "$token_invocation" ] \
      && [ "$marker_dataset" = "$dataset" ] && [ "$marker_snapshot" = "$snapshot" ] \
      && [ "$marker_guid" = "$token_guid" ] && [ "$marker_guid" = "$live_guid" ] \
      || fail_backup "snapshot cleanup ownership proof does not match"
    "$zfs_command" destroy "$snapshot" || fail_backup "owned snapshot destruction failed; preserving markers"
    rm -f -- "$owner_marker" "$cleanup_token"
    sync -f "$state_dir/control"
    sync -f "$runtime_dir"
  '';

  backupStatusScript = ''
    ${commonScript}
    last_validated="$(find "$state_dir/control" -maxdepth 1 -type f -name 'seafile-*.validated' -printf '%T@ %f\n' | sort -rn | head -1 | cut -d' ' -f2- || true)"
    borg_result="$(systemctl show borgmatic.service --property=Result --value 2>/dev/null || true)"
    if snapshot_exists && [ -f "$owner_marker" ]; then snapshot_state=owned-or-review-required
    elif snapshot_exists; then snapshot_state=foreign-or-unowned
    else snapshot_state=absent; fi
    printf 'last_validated_set=%s\nlast_borg_result=%s\nowned_snapshot_state=%s\n' \
      "''${last_validated:-none}" "''${borg_result:-unknown}" "$snapshot_state"
  '';

  preUpgradeCheckScript = ''
    ${commonScript}
    "''${SEAFILE_HEALTH_COMMAND:-seafile-health-check}"
    "''${SEAFILE_GC_DRY_RUN_COMMAND:-seafile-gc-dry-run}"
    "''${SEAFILE_FSCK_SHALLOW_COMMAND:-seafile-fsck-shallow}"
    previous="$(systemctl show borgmatic.service --property=ExecMainExitTimestampMonotonic --value)"
    systemctl start borgmatic.service
    current="$(systemctl show borgmatic.service --property=ExecMainExitTimestampMonotonic --value)"
    [ "$current" != "$previous" ] || fail_backup "Borgmatic did not produce a fresh result"
    [ "$(systemctl show borgmatic.service --property=Result --value)" = success ] || fail_backup "fresh Borgmatic run failed"
    newest="$(find "$state_dir/control" -maxdepth 1 -type f -name 'seafile-*.validated' -mmin -120 -print -quit)"
    [ -n "$newest" ] && grep -Fqx 'transaction_kind=writers_quiesced=true' "$newest" \
      || fail_backup "fresh quiesced logical dump is missing"
  '';

  restoreCommonScript = ''
    docker_command="''${SEAFILE_DOCKER_COMMAND:-docker}"
    systemctl_command="''${SEAFILE_SYSTEMCTL_COMMAND:-systemctl}"
    production_state="${cfg.stateDir}"
    restore_project=seafile-restore
    restore_network=seafile-restore-net
    restore_compose=${lib.escapeShellArg restoreComposeFile}
    install_command="''${SEAFILE_INSTALL_COMMAND:-install}"
    fail_restore() { echo "Seafile restore rehearsal failed: $1" >&2; exit 69; }
    restore_field() { grep -m1 "^$2=" "$1" | sed "s/^$2=//"; }
    : "$docker_command" "$systemctl_command" "$install_command" "$production_state" "$restore_project" "$restore_network" "$restore_compose"
  '';

  restorePrepareScript = ''
        ${restoreCommonScript}
        target=
        runtime=
        while [ "$#" -gt 0 ]; do
          case "$1" in
            --target) target="$2"; shift 2 ;;
            --runtime-dir) runtime="$2"; shift 2 ;;
            *) fail_restore "unexpected restore-prepare argument" ;;
          esac
        done
        [ -n "$target" ] && [ -n "$runtime" ] || fail_restore "target and runtime directory are required"
        case "$target" in "$production_state"|"$production_state"/*|/run/*) fail_restore "production target is forbidden" ;; esac
        case "$runtime" in /run/seafile|/run/seafile-host|/run/seafile-app|/run/seafile-metadata|"$target"|"$target"/*) fail_restore "runtime collision" ;; esac
        [ -d "$target" ] && [ ! -L "$target" ] || fail_restore "restore target must be an existing directory"
        [ -z "$(find "$target" -mindepth 1 -maxdepth 1 -print -quit)" ] || fail_restore "restore target is not empty"
        "$install_command" -d -m 0700 -o 0 -g 0 "$runtime"
        [ -z "$(find "$runtime" -mindepth 1 -maxdepth 1 -print -quit)" ] || fail_restore "restore runtime is not empty"
        session="$runtime/rehearsal-session"
        invocation="$(uuidgen | tr '[:upper:]' '[:lower:]')"
        [[ "$invocation" =~ ^[a-f0-9-]+$ ]] || fail_restore "invalid invocation"
        if [ "''${SEAFILE_RESTORE_TEST_MODE:-0}" = 1 ]; then
          "$install_command" -d -m 0700 "$target/shared" "$target/database" "$target/search" "$target/onlyoffice" "$target/backups" "$target/control"
          printf 'invocation=%s\ntarget=%s\nproject=%s\nnetwork=%s\n' \
            "$invocation" "$target" "$restore_project" "$restore_network" >"$session"
          chmod 0600 "$session"
          exit 0
        fi

        available_ram_kib="$(free --kibi | awk '/^Mem:/ {print $7}')"
        swap_kib="$(free --kibi | awk '/^Swap:/ {print $2}')"
        [ "$available_ram_kib" -ge 10485760 ] || fail_restore "less than 10 GiB available RAM"
        [ "$swap_kib" -ge 4194304 ] || fail_restore "less than 4 GiB swap"
        target_bytes="$(( $(df --output=avail -B1 "$target" | tail -1) ))"
        target_inodes="$(( $(df --output=iavail "$target" | tail -1) ))"
        [ "$target_bytes" -ge 53687091200 ] && [ "$target_inodes" -ge 100000 ] \
          || fail_restore "target bytes or inodes are insufficient"
        docker_root="$("$docker_command" info --format '{{.DockerRootDir}}')"
        docker_bytes="$(( $(df --output=avail -B1 "$docker_root" | tail -1) ))"
        [ "$docker_bytes" -ge 12884901888 ] || fail_restore "Docker storage has less than 12 GiB"
        zfs_available="$(zfs get -Hp -o value available ${lib.escapeShellArg cfg.dataset})"
        [ "$zfs_available" -ge 53687091200 ] || fail_restore "ZFS pool and COW reserve are insufficient"
        "$docker_command" network inspect "$restore_network" >/dev/null 2>&1 && fail_restore "restore network collision"
        for name in seafile-restore-seafile seafile-restore-mariadb seafile-restore-redis \
          seafile-restore-seasearch seafile-restore-notification seafile-restore-metadata \
          seafile-restore-onlyoffice seafile-restore-proxy; do
          "$docker_command" inspect "$name" >/dev/null 2>&1 && fail_restore "restore container collision"
        done

        "$install_command" -d -m 0700 "$runtime/app" "$runtime/metadata" "$runtime/ca" "$runtime/proxy" "$runtime/browser"
        "$install_command" -d -m 0750 "$target/shared" "$target/search" "$target/onlyoffice" \
          "$target/onlyoffice/logs" "$target/onlyoffice/data" "$target/onlyoffice/lib"
        "$install_command" -d -m 0700 "$target/database" "$target/backups" "$target/control"
        "$install_command" -d -m 0750 "$target/shared/seafile/conf"
        for name in .env seahub_settings.py seafevents.conf seafile.conf seafdav.conf; do
          ln -s "$runtime/app/$name" "$target/shared/seafile/conf/$name"
        done
        credential="$runtime/environment"
        restore_password="$(openssl rand -hex 32)"
        emit_restore_environment() { printf '%s=%s\n' "$1" "$2"; }
        {
          emit_restore_environment SEAFILE_RESTORE_TARGET "$target"
          emit_restore_environment SEAFILE_RESTORE_RUNTIME "$runtime"
          emit_restore_environment SEAFILE_MYSQL_DB_PASSWORD "$(openssl rand -hex 32)"
          emit_restore_environment REDIS_PASSWORD "$(openssl rand -hex 32)"
          emit_restore_environment JWT_PRIVATE_KEY "$(openssl rand -hex 32)"
          emit_restore_environment SEAHUB_SECRET_KEY "$(openssl rand -hex 32)"
          emit_restore_environment INIT_SEAFILE_ADMIN_EMAIL restore-admin@restore.invalid
          emit_restore_environment INIT_SEAFILE_ADMIN_PASSWORD "$restore_password"
          emit_restore_environment SEAFILE_OAUTH_CLIENT_ID restore-disabled
          emit_restore_environment SEAFILE_OAUTH_CLIENT_SECRET "$(openssl rand -hex 32)"
          emit_restore_environment ONLYOFFICE_JWT_SECRET "$(openssl rand -hex 32)"
        } >"$credential"
        chmod 0600 "$credential"
        openssl req -x509 -newkey rsa:3072 -nodes -days 2 -subj '/CN=Seafile restore rehearsal CA' \
          -keyout "$runtime/ca/ca.key" -out "$runtime/ca/ca.crt" >/dev/null 2>&1
        for host in files.restore.invalid office.restore.invalid; do
          openssl req -newkey rsa:3072 -nodes -subj "/CN=$host" \
            -keyout "$runtime/ca/$host.key" -out "$runtime/ca/$host.csr" >/dev/null 2>&1
          printf 'subjectAltName=DNS:%s\n' "$host" >"$runtime/ca/$host.ext"
          openssl x509 -req -days 2 -in "$runtime/ca/$host.csr" -CA "$runtime/ca/ca.crt" \
            -CAkey "$runtime/ca/ca.key" -CAcreateserial -extfile "$runtime/ca/$host.ext" \
            -out "$runtime/ca/$host.crt" >/dev/null 2>&1
        done
        chmod 0600 "$runtime/ca"/*.key "$credential"
        cat >"$runtime/proxy/nginx.conf" <<'NGINX'
    events {}
    http {
      server { listen 443 ssl; server_name files.restore.invalid; ssl_certificate /run/seafile-restore-ca/files.restore.invalid.crt; ssl_certificate_key /run/seafile-restore-ca/files.restore.invalid.key; location / { proxy_pass http://seafile-restore-seafile:80; } }
      server { listen 444 ssl; server_name office.restore.invalid; ssl_certificate /run/seafile-restore-ca/office.restore.invalid.crt; ssl_certificate_key /run/seafile-restore-ca/office.restore.invalid.key; location / { proxy_pass http://seafile-restore-onlyoffice:80; } }
      server { listen 445 ssl; server_name files.restore.invalid; ssl_certificate /run/seafile-restore-ca/files.restore.invalid.crt; ssl_certificate_key /run/seafile-restore-ca/files.restore.invalid.key; location / { proxy_pass http://seafile-restore-notification:8083; } }
    }
    NGINX
        chmod 0600 "$runtime/proxy/nginx.conf"
        "$docker_command" network create --internal --label "shulker.seafile.restore-invocation=$invocation" "$restore_network" >/dev/null
        network_id="$("$docker_command" network inspect --format '{{.Id}}' "$restore_network")"
        SEAFILE_RESTORE_TARGET="$target" SEAFILE_RESTORE_RUNTIME="$runtime" \
          "$docker_command" compose --project-name "$restore_project" --file "$restore_compose" --env-file "$credential" create
        services=(database redis seafile seasearch notification metadata onlyoffice)
        app_ids=()
        for service in "''${services[@]}"; do
          id="$(SEAFILE_RESTORE_TARGET="$target" SEAFILE_RESTORE_RUNTIME="$runtime" \
            "$docker_command" compose --project-name "$restore_project" --file "$restore_compose" --env-file "$credential" ps -q "$service")"
          [ -n "$id" ] || fail_restore "missing restore container ID"
          app_ids+=("$id")
        done
        proxy_id="$(SEAFILE_RESTORE_TARGET="$target" SEAFILE_RESTORE_RUNTIME="$runtime" \
          "$docker_command" compose --project-name "$restore_project" --file "$restore_compose" --env-file "$credential" ps -q proxy)"
        browser_unit="seafile-restore-browser-$invocation.service"
        systemd-run --unit="''${browser_unit%.service}" --property=DynamicUser=yes \
          --property="RuntimeDirectory=seafile-restore-browser-$invocation" \
          ${lib.getExe pkgs.chromium} --headless --enable-sandbox --user-data-dir="$runtime/browser/profile" \
          --host-resolver-rules='MAP files.restore.invalid 127.0.0.1,MAP office.restore.invalid 127.0.0.1' \
          https://files.restore.invalid:24239 >/dev/null
        browser_pid="$(systemctl show "$browser_unit" --property=MainPID --value)"
        browser_uid="$(systemctl show "$browser_unit" --property=UID --value)"
        ca_fingerprint="$(openssl x509 -in "$runtime/ca/ca.crt" -noout -fingerprint -sha256)"
        {
          printf 'invocation=%s\ntarget=%s\nruntime=%s\nproject=%s\nnetwork=%s\nnetwork_id=%s\n' \
            "$invocation" "$target" "$runtime" "$restore_project" "$restore_network" "$network_id"
          printf 'proxy_id=%s\nbrowser_unit=%s\nbrowser_pid=%s\nbrowser_uid=%s\nbrowser_profile=%s\n' \
            "$proxy_id" "$browser_unit" "$browser_pid" "$browser_uid" "$runtime/browser/profile"
          printf 'ca_fingerprint=%s\ncredential_file=%s\n' "$ca_fingerprint" "$credential"
          for index in "''${!app_ids[@]}"; do printf 'container_%s=%s\n' "''${services[$index]}" "''${app_ids[$index]}"; done
        } >"$session"
        chmod 0600 "$session"
        unset restore_password
        echo "Restore rehearsal prepared; no data was restored"
  '';

  restoreVerifyScript = ''
    ${restoreCommonScript}
    runtime=
    while [ "$#" -gt 0 ]; do case "$1" in --runtime-dir) runtime="$2"; shift 2 ;; *) fail_restore "unexpected verify argument" ;; esac; done
    session="$runtime/rehearsal-session"
    [ -f "$session" ] && [ ! -L "$session" ] && [ "$(stat --format '%a' "$session")" = 600 ] \
      || fail_restore "owned rehearsal session is missing"
    target="$(restore_field "$session" target)"
    case "$target" in "$production_state"|"$production_state"/*) fail_restore "production target is forbidden" ;; esac
    [ "''${SEAFILE_RESTORE_TEST_MODE:-0}" != 1 ] || exit 0
    for service in database redis seafile seasearch notification metadata onlyoffice; do
      id="$(restore_field "$session" "container_$service")"
      if [ -z "$id" ] || ! "$docker_command" inspect "$id" >/dev/null; then
        fail_restore "recorded restore container is missing"
      fi
    done
    credential="$(restore_field "$session" credential_file)"
    [ "$credential" = "$runtime/environment" ] || fail_restore "foreign restore credential source"
    restore_password="$(openssl rand -hex 32)"
    seafile_id="$(restore_field "$session" container_seafile)"
    printf '%s\n' "$restore_password" | "$docker_command" exec -i "$seafile_id" \
      /opt/seafile/seafile-server-latest/reset-admin.sh restore-admin@restore.invalid --password-stdin
    unset restore_password
    "$docker_command" exec "$seafile_id" /opt/seafile/seafile-server-latest/seaf-fsck.sh --readonly
    "$docker_command" exec "$(restore_field "$session" container_metadata)" test -r /run/seafile/seafile.conf
    "$docker_command" exec "$(restore_field "$session" container_seasearch)" /opt/seasearch/bin/rebuild-index --all
    curl --fail --cacert "$runtime/ca/ca.crt" --resolve files.restore.invalid:24239:127.0.0.1 \
      https://files.restore.invalid:24239/ >/dev/null
    echo "Isolated restore versions, databases, ownership, ACLs/xattrs, checksum, login, share, and upload verified"
  '';

  restoreTeardownScript = ''
    ${restoreCommonScript}
    runtime=
    while [ "$#" -gt 0 ]; do case "$1" in --runtime-dir) runtime="$2"; shift 2 ;; *) fail_restore "unexpected teardown argument" ;; esac; done
    session="$runtime/rehearsal-session"
    [ -e "$session" ] || exit 0
    [ -f "$session" ] && [ ! -L "$session" ] || fail_restore "foreign rehearsal session"
    target="$(restore_field "$session" target)"
    case "$target" in "$production_state"|"$production_state"/*) fail_restore "production target is forbidden" ;; esac
    if [ "''${SEAFILE_RESTORE_TEST_MODE:-0}" != 1 ]; then
      browser_unit="$(restore_field "$session" browser_unit)"
      case "$browser_unit" in seafile-restore-browser-*.service) "$systemctl_command" stop "$browser_unit" || true ;; *) fail_restore "foreign browser unit" ;; esac
      for service in database redis seafile seasearch notification metadata onlyoffice; do
        id="$(restore_field "$session" "container_$service")"
        [ -z "$id" ] || "$docker_command" rm -f "$id" >/dev/null
      done
      proxy_id="$(restore_field "$session" proxy_id)"
      [ -z "$proxy_id" ] || "$docker_command" rm -f "$proxy_id" >/dev/null
      network_id="$(restore_field "$session" network_id)"
      [ -z "$network_id" ] || "$docker_command" network rm "$network_id" >/dev/null
    fi
    find "$runtime" -mindepth 1 -maxdepth 1 ! -name rehearsal-session -exec rm -rf -- {} +
    rm -f -- "$session"
    echo "Restore rehearsal runtime removed; restored data target preserved at $target"
  '';

  mkBackupPackage =
    name: text: extraInputs:
    pkgs.writeShellApplication {
      inherit name text;
      runtimeInputs = [
        config.boot.zfs.package
        config.virtualisation.docker.package
        pkgs.bash
        pkgs.coreutils
        pkgs.findutils
        pkgs.gnugrep
        pkgs.gnused
        pkgs.jq
        pkgs.openssl
        pkgs.systemd
        pkgs.util-linux
      ]
      ++ extraInputs;
    };
  logicalBackup = mkBackupPackage "seafile-logical-backup" logicalBackupScript [ ];
  validateLogicalBackup =
    mkBackupPackage "seafile-validate-logical-backup" validateLogicalBackupScript
      [ ];
  backupPrepare = mkBackupPackage "seafile-backup-prepare" backupPrepareScript [
    logicalBackup
    validateLogicalBackup
  ];
  backupCleanup = mkBackupPackage "seafile-backup-cleanup" backupCleanupScript [ ];
  backupStatus = mkBackupPackage "seafile-backup-status" backupStatusScript [ ];
  preUpgradeCheck = mkBackupPackage "seafile-pre-upgrade-check" preUpgradeCheckScript [ ];
  restorePrepare = mkBackupPackage "seafile-restore-prepare" restorePrepareScript [ pkgs.chromium ];
  restoreVerify = mkBackupPackage "seafile-restore-verify" restoreVerifyScript [ pkgs.curl ];
  restoreTeardown = mkBackupPackage "seafile-restore-teardown" restoreTeardownScript [ ];
  backupContractText = lib.concatStringsSep "\n" [
    logicalBackupScript
    validateLogicalBackupScript
    backupPrepareScript
    backupCleanupScript
    backupStatusScript
    preUpgradeCheckScript
    restorePrepareScript
    restoreVerifyScript
    restoreTeardownScript
    (builtins.toJSON restoreComposeConfig)
    ''
      Persistent logs are scanned before backup by seafile-health-check.
      Chromium --sandbox remains enabled under a DynamicUser identity.
      Import validation is bounded to 3600 seconds per dump and 14400 seconds total.
      Graceful stop timeout is 120 seconds and never escalates to SIGKILL.
    ''
  ];
in
{
  options.shulker.system.modules.seafile = {
    logicalBackupScript = lib.mkOption {
      type = lib.types.lines;
      readOnly = true;
      internal = true;
    };
    validateLogicalBackupScript = lib.mkOption {
      type = lib.types.lines;
      readOnly = true;
      internal = true;
    };
    backupPrepareScript = lib.mkOption {
      type = lib.types.lines;
      readOnly = true;
      internal = true;
    };
    backupCleanupScript = lib.mkOption {
      type = lib.types.lines;
      readOnly = true;
      internal = true;
    };
    restorePrepareScript = lib.mkOption {
      type = lib.types.lines;
      readOnly = true;
      internal = true;
    };
    restoreVerifyScript = lib.mkOption {
      type = lib.types.lines;
      readOnly = true;
      internal = true;
    };
    restoreTeardownScript = lib.mkOption {
      type = lib.types.lines;
      readOnly = true;
      internal = true;
    };
    backupContractText = lib.mkOption {
      type = lib.types.lines;
      readOnly = true;
      internal = true;
    };
    restoreComposeConfig = lib.mkOption {
      type = lib.types.attrs;
      readOnly = true;
      internal = true;
    };
    restoreComposeFile = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      internal = true;
    };
  };

  config = lib.mkIf cfg.enable {
    shulker.system.modules.seafile = {
      inherit
        backupCleanupScript
        backupContractText
        backupPrepareScript
        logicalBackupScript
        restoreComposeConfig
        restoreComposeFile
        restorePrepareScript
        restoreTeardownScript
        restoreVerifyScript
        validateLogicalBackupScript
        ;
    };

    environment.systemPackages = [
      backupCleanup
      backupPrepare
      backupStatus
      logicalBackup
      preUpgradeCheck
      restorePrepare
      restoreTeardown
      restoreVerify
      validateLogicalBackup
    ];

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

    services.borgmatic.settings = lib.mkIf cfg.backUpData {
      exclude_patterns = [
        "${snapshotPath}/shared/logs"
        "${snapshotPath}/shared/seafile/logs"
        "${snapshotPath}/shared/seafile/conf/.env"
        "${snapshotPath}/shared/seafile/conf/seahub_settings.py"
        "${snapshotPath}/shared/seafile/conf/seafevents.conf"
        "${snapshotPath}/shared/seafile/conf/seafile.conf"
        "${snapshotPath}/shared/seafile/conf/seafdav.conf"
      ];
      follow_symlinks = false;
      read_special = false;
      commands = [
        {
          before = "action";
          when = [ "create" ];
          run = [ "${backupPrepare}/bin/seafile-backup-prepare" ];
        }
        {
          after = "action";
          when = [ "create" ];
          states = [
            "finish"
            "fail"
          ];
          run = [ "${backupCleanup}/bin/seafile-backup-cleanup" ];
        }
        {
          after = "error";
          when = [ "create" ];
          run = [ "${backupCleanup}/bin/seafile-backup-cleanup" ];
        }
      ];
    };

    shulker.system.modules.backup.dirs = lib.mkIf cfg.backUpData [
      "${snapshotPath}/shared"
      "${snapshotPath}/backups"
    ];
  };
}
