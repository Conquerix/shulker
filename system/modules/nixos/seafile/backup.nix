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
  restoreIdentifyNativeAdminScript = ''
    from seaserv import ccnet_api
    from seahub.auth.models import SocialAuthUser

    license_user_limit = ${toString cfg.licenseUserLimit}
    users = ccnet_api.get_emailusers("DB", -1, -1)
    active_users = [user for user in users if user.is_active]
    oauth_usernames = set(
        SocialAuthUser.objects.filter(provider="pocket-id").values_list("username", flat=True)
    )
    oauth_users = [user for user in active_users if user.email in oauth_usernames]
    disabled_oauth_users = [
        user for user in users if not user.is_active and user.email in oauth_usernames
    ]
    native_admins = [
        user
        for user in active_users
        if user.email not in oauth_usernames and user.password != "!" and user.is_staff
    ]
    recognized = len(oauth_users) + len(native_admins)
    valid = (
        len(active_users) <= license_user_limit
        and 1 <= len(oauth_users) <= 2
        and all(user.password == "!" for user in oauth_users)
        and not disabled_oauth_users
        and len(native_admins) == 1
        and native_admins[0].email != "restore-admin@restore.invalid"
        and recognized == len(active_users)
    )
    if not valid:
        raise RuntimeError("Restored identity boundary is not safe for native recovery")
    print(native_admins[0].email)
  '';
  restoreIdentifyNativeAdmin = pkgs.writeText "seafile-restore-identify-native-admin.py" restoreIdentifyNativeAdminScript;
  restoreVerifyNativeAdminScript = ''
    import os

    from seaserv import ccnet_api
    from seahub.auth.models import SocialAuthUser
    from seahub.base.accounts import User

    license_user_limit = ${toString cfg.licenseUserLimit}
    native_email = os.environ["RESTORE_NATIVE_EMAIL"]
    users = ccnet_api.get_emailusers("DB", -1, -1)
    active_users = [user for user in users if user.is_active]
    oauth_usernames = set(
        SocialAuthUser.objects.filter(provider="pocket-id").values_list("username", flat=True)
    )
    oauth_users = [user for user in active_users if user.email in oauth_usernames]
    disabled_oauth_users = [
        user for user in users if not user.is_active and user.email in oauth_usernames
    ]
    native_admins = [
        user
        for user in active_users
        if user.email not in oauth_usernames and user.password != "!" and user.is_staff
    ]
    recognized = len(oauth_users) + len(native_admins)
    valid = (
        len(active_users) <= license_user_limit
        and 1 <= len(oauth_users) <= 2
        and all(user.password == "!" for user in oauth_users)
        and not disabled_oauth_users
        and len(native_admins) == 1
        and native_admins[0].email != "restore-admin@restore.invalid"
        and recognized == len(active_users)
    )
    if not valid:
        raise RuntimeError("Native recovery changed the restored identity boundary")
    if native_admins[0].email != native_email:
        raise RuntimeError("Native recovery targeted an unexpected restored identity")
    user = User.objects.get(email=native_email)
    if not user.check_password(os.environ["RESTORE_PASSWORD"]):
        raise RuntimeError("Native restore-only credential verification failed")
  '';
  restoreVerifyNativeAdmin = pkgs.writeText "seafile-restore-verify-native-admin.py" restoreVerifyNativeAdminScript;
  restoreResetNativeAdminScript = ''
    import os

    from seahub.auth.models import SocialAuthUser
    from seahub.base.accounts import User

    native_email = os.environ["RESTORE_NATIVE_EMAIL"]
    user = User.objects.get(email=native_email)
    if not user.is_active or not user.is_staff or user.enc_password == "!":
        raise RuntimeError("Refusing to reset a non-native restored administrator")
    if SocialAuthUser.objects.filter(username=user.username, provider="pocket-id").exists():
        raise RuntimeError("Refusing to reset an OAuth-linked restored administrator")
    user.set_password(os.environ["RESTORE_PASSWORD"])
    if user.save() != 0:
        raise RuntimeError("Seafile refused the restore-only password update")
    refreshed = User.objects.get(email=native_email)
    if not refreshed.check_password(os.environ["RESTORE_PASSWORD"]):
        raise RuntimeError("Restore-only password update did not persist")
  '';
  restoreResetNativeAdmin = pkgs.writeText "seafile-restore-reset-native-admin.py" restoreResetNativeAdminScript;
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
    enableExternalEgress = false;
    serviceLabels = {
      "shulker.seafile.restore-invocation" =
        "\${SEAFILE_RESTORE_INVOCATION:?SEAFILE_RESTORE_INVOCATION is required}";
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
      labels = {
        "shulker.seafile.restore-invocation" =
          "\${SEAFILE_RESTORE_INVOCATION:?SEAFILE_RESTORE_INVOCATION is required}";
      };
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
  restoreBootstrapComposeFile = restoreBase.bootstrapComposeFile;

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
    password_count="$(grep -c '^SEAFILE_MYSQL_DB_PASSWORD=' "$environment_file" || true)"
    [ "$password_count" -eq 1 ] || fail_backup "runtime database credential is unavailable"
    MYSQL_PWD="$(sed -n 's/^SEAFILE_MYSQL_DB_PASSWORD=//p' "$environment_file")"
    [ -n "$MYSQL_PWD" ] || fail_backup "runtime database credential is empty"
    export MYSQL_PWD

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
    compose_file="''${SEAFILE_COMPOSE_FILE:-${cfg.composeFile}}"
    compose_environment="''${SEAFILE_COMPOSE_ENVIRONMENT:-/run/seafile-host/compose.environment}"
    compose_established() {
      "$docker_command" compose --project-name seafile --file "$compose_file" \
        --env-file "$compose_environment" "$@"
    }
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

    stop_gracefully() {
      local container="$1"
      "$docker_command" kill --signal TERM "$container" >/dev/null
      stopped+=("$container")
      [ "''${SEAFILE_TEST_NO_SLEEP:-0}" != 1 ] || return 0
      for _ in $(seq 1 120); do
        [ "$("$docker_command" inspect --format '{{.State.Running}}' "$container" 2>/dev/null)" = false ] \
          && return 0
        sleep 1
      done
      fail_backup "$container did not stop after TERM; refusing SIGKILL"
    }

    was_stopped() {
      local expected="$1" container
      for container in "''${stopped[@]}"; do
        [ "$container" = "$expected" ] && return 0
      done
      return 1
    }

    restart_owned() {
      local mapping container service
      if [ "$onlyoffice_prepare_attempted" -eq 1 ] && [ "$onlyoffice_original" -eq 1 ] \
        && ! was_stopped seafile-onlyoffice; then
        stop_gracefully seafile-onlyoffice || return $?
      fi
      for mapping in \
        seafile-mariadb:database \
        seafile-redis:redis \
        seafile:seafile \
        seafile-seasearch:seasearch \
        seafile-notification:notification \
        seafile-metadata:metadata \
        seafile-onlyoffice:onlyoffice
      do
        container="''${mapping%%:*}"
        service="''${mapping#*:}"
        if was_stopped "$container"; then
          compose_established up --detach --no-deps --no-recreate --wait --wait-timeout 1800 "$service" \
            || return $?
        fi
      done
      stopped=()
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
      restart_status=0
      restart_owned || restart_status=$?
      [ "$status" -eq 0 ] || destroy_current_snapshot
      if [ "$status" -eq 0 ] && [ "$restart_status" -ne 0 ]; then status="$restart_status"; fi
      exit "$status"
    }
    trap recover_prepare EXIT
    trap 'exit 75' HUP INT TERM

    onlyoffice_prepare_attempted=1
    "$timeout_command" 330 "$docker_command" exec seafile-onlyoffice documentserver-prepare4shutdown.sh
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
    if [ -z "$newest" ] || ! grep -Fqx 'transaction_kind=writers_quiesced=true' "$newest"; then
      fail_backup "fresh quiesced logical dump is missing"
    fi
  '';

  restoreCommonScript = ''
    docker_command="''${SEAFILE_DOCKER_COMMAND:-docker}"
    systemctl_command="''${SEAFILE_SYSTEMCTL_COMMAND:-systemctl}"
    curl_command="''${SEAFILE_CURL_COMMAND:-curl}"
    timeout_command="''${SEAFILE_TIMEOUT_COMMAND:-timeout}"
    findmnt_command="''${SEAFILE_FINDMNT_COMMAND:-findmnt}"
    free_command="''${SEAFILE_FREE_COMMAND:-free}"
    df_command="''${SEAFILE_DF_COMMAND:-df}"
    zfs_command="''${SEAFILE_ZFS_COMMAND:-zfs}"
    render_command="''${SEAFILE_RENDER_RUNTIME_CONFIG_COMMAND:-${lib.getExe cfg.renderRuntimeConfigPackage}}"
    production_state="''${SEAFILE_STATE_DIR:-${cfg.stateDir}}"
    restore_project=seafile-restore
    restore_network=seafile-restore-net
    restore_compose=${lib.escapeShellArg restoreComposeFile}
    restore_bootstrap_compose=${lib.escapeShellArg restoreBootstrapComposeFile}
    restore_invocation=
    install_command="''${SEAFILE_INSTALL_COMMAND:-install}"
    fail_restore() { echo "Seafile restore rehearsal failed: $1" >&2; exit 69; }
    path_present() { [ -e "$1" ] || [ -L "$1" ]; }
    restore_field() {
      local file="$1" key="$2" count value
      [ -f "$file" ] && [ ! -L "$file" ] || return 1
      count="$(grep -c "^$key=" "$file" || true)"
      [ "$count" -eq 1 ] || return 1
      value="$(sed -n "s/^$key=//p" "$file")"
      [ -n "$value" ] || return 1
      printf '%s\n' "$value"
    }
    require_safe_empty_directory() {
      local directory="$1" purpose="$2"
      [ -d "$directory" ] && [ ! -L "$directory" ] \
        || fail_restore "$purpose must be an existing dedicated directory"
      [ "$(stat --format '%a' "$directory")" = 700 ] \
        || fail_restore "$purpose must have mode 0700"
      if [ "''${SEAFILE_TEST_SKIP_OWNERSHIP:-0}" != 1 ]; then
        [ "$(stat --format '%u:%g' "$directory")" = 0:0 ] \
          || fail_restore "$purpose must be owned by root"
      fi
      [ -z "$(find "$directory" -mindepth 1 -maxdepth 1 -print -quit)" ] \
        || fail_restore "$purpose is not empty"
    }
    compose_restore() {
      SEAFILE_RESTORE_TARGET="$target" SEAFILE_RESTORE_RUNTIME="$runtime" \
        SEAFILE_RESTORE_INVOCATION="''${restore_invocation:?restore invocation is unavailable}" \
        "$docker_command" compose --project-name "$restore_project" \
        --file "$restore_compose" --env-file "$runtime/compose.environment" "$@"
    }
    compose_restore_bootstrap() {
      SEAFILE_RESTORE_TARGET="$target" SEAFILE_RESTORE_RUNTIME="$runtime" \
        SEAFILE_RESTORE_INVOCATION="''${restore_invocation:?restore invocation is unavailable}" \
        "$docker_command" compose --project-name "$restore_project" \
        --file "$restore_compose" --file "$restore_bootstrap_compose" \
        --env-file "$runtime/source.environment" "$@"
    }
    : "$docker_command" "$systemctl_command" "$curl_command" "$timeout_command" "$findmnt_command" \
      "$free_command" "$df_command" "$zfs_command" "$render_command" \
      "$install_command" "$production_state" "$restore_project" "$restore_network" \
      "$restore_compose" "$restore_bootstrap_compose"
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
    [[ "$target" =~ ^/[A-Za-z0-9._/-]+$ ]] && [[ "$runtime" =~ ^/[A-Za-z0-9._/-]+$ ]] \
      || fail_restore "restore paths contain unsupported characters"
    canonical_production="$(realpath -e -- "$production_state")" \
      || fail_restore "production state cannot be canonicalized"
    canonical_target="$(realpath -e -- "$target")" \
      || fail_restore "restore target cannot be canonicalized"
    [ "$canonical_target" = "$target" ] \
      || fail_restore "restore target must be canonical and contain no symlinked parent"
    case "$canonical_target" in
      /|"$canonical_production"|"$canonical_production"/*|/run/*) fail_restore "production or unsafe target is forbidden" ;;
      /*) ;;
      *) fail_restore "restore target must be absolute" ;;
    esac
    [ "$(stat --format '%d:%i' "$canonical_target")" != "$(stat --format '%d:%i' "$canonical_production")" ] \
      || fail_restore "restore target aliases production state"
    production_source="$($findmnt_command --noheadings --output SOURCE --target "$canonical_production")" \
      || fail_restore "production mount source cannot be verified"
    target_source="$($findmnt_command --noheadings --output SOURCE --target "$canonical_target")" \
      || fail_restore "restore target mount source cannot be verified"
    production_source="''${production_source%%\[*}"
    target_source="''${target_source%%\[*}"
    [ -n "$production_source" ] && [ -n "$target_source" ] && [ "$target_source" != "$production_source" ] \
      || fail_restore "restore target shares the production mount source"
    case "$runtime" in
      /|/etc|/etc/*|/run/seafile|/run/seafile-host|/run/seafile-app|/run/seafile-metadata|"$target"|"$target"/*)
        fail_restore "runtime collision"
        ;;
      /*) ;;
      *) fail_restore "restore runtime must be absolute" ;;
    esac
    require_safe_empty_directory "$target" "restore target"
    if path_present "$runtime"; then
      canonical_runtime="$(realpath -e -- "$runtime")" \
        || fail_restore "restore runtime cannot be canonicalized"
      [ "$canonical_runtime" = "$runtime" ] \
        || fail_restore "restore runtime must be canonical and contain no symlinked parent"
      case "$canonical_runtime" in
        "$canonical_production"|"$canonical_production"/*|"$canonical_target"|"$canonical_target"/*)
          fail_restore "restore runtime aliases protected state"
          ;;
      esac
      [ "$(stat --format '%d:%i' "$canonical_runtime")" != "$(stat --format '%d:%i' "$canonical_production")" ] \
        || fail_restore "restore runtime aliases production state"
      runtime_source="$($findmnt_command --noheadings --output SOURCE --target "$canonical_runtime")" \
        || fail_restore "restore runtime mount source cannot be verified"
      runtime_source="''${runtime_source%%\[*}"
      [ -n "$runtime_source" ] && [ "$runtime_source" != "$production_source" ] \
        || fail_restore "restore runtime shares the production mount source"
      require_safe_empty_directory "$runtime" "restore runtime"
      runtime_created=0
    else
      runtime_parent="''${runtime%/*}"
      canonical_runtime_parent="$(realpath -e -- "$runtime_parent")" \
        || fail_restore "restore runtime parent cannot be canonicalized"
      [ "$canonical_runtime_parent" = "$runtime_parent" ] \
        || fail_restore "restore runtime parent must be canonical and not symlinked"
      case "$canonical_runtime_parent" in
        "$canonical_production"|"$canonical_production"/*|"$canonical_target"|"$canonical_target"/*)
          fail_restore "restore runtime parent aliases protected state"
          ;;
      esac
      [ "$(stat --format '%d:%i' "$canonical_runtime_parent")" != "$(stat --format '%d:%i' "$canonical_production")" ] \
        || fail_restore "restore runtime parent aliases production state"
      runtime_parent_source="$($findmnt_command --noheadings --output SOURCE --target "$canonical_runtime_parent")" \
        || fail_restore "restore runtime parent mount source cannot be verified"
      runtime_parent_source="''${runtime_parent_source%%\[*}"
      [ -n "$runtime_parent_source" ] && [ "$runtime_parent_source" != "$production_source" ] \
        || fail_restore "restore runtime parent shares the production mount source"
      [ -d "$runtime_parent" ] && [ ! -L "$runtime_parent" ] \
        || fail_restore "restore runtime parent is unsafe"
      if [ "''${SEAFILE_TEST_SKIP_OWNERSHIP:-0}" != 1 ]; then
        [ "$(stat --format '%u' "$runtime_parent")" = 0 ] \
          || fail_restore "restore runtime parent is not root-owned"
      fi
      "$install_command" -d -m 0700 -o 0 -g 0 "$runtime"
      runtime_created=1
    fi
    session="$runtime/rehearsal-session"
    invocation="$(uuidgen | tr '[:upper:]' '[:lower:]')"
    [[ "$invocation" =~ ^[a-f0-9-]+$ ]] || fail_restore "invalid invocation"
    restore_invocation="$invocation"
    target_prepared=0
    session_written=0
    restore_names=(
      seafile-restore-seafile seafile-restore-mariadb seafile-restore-redis
      seafile-restore-seasearch seafile-restore-notification seafile-restore-metadata
      seafile-restore-onlyoffice seafile-restore-proxy
    )

    rollback_prepare() {
      status=$?
      trap - EXIT
      if [ "$status" -ne 0 ] && [ "$session_written" -eq 0 ]; then
        cleanup_failed=0
        for name in "''${restore_names[@]}"; do
          if "$docker_command" inspect "$name" >/dev/null 2>&1; then
            owner="$("$docker_command" inspect --format '{{index .Config.Labels "com.docker.compose.project"}}' "$name" 2>/dev/null || true)"
            container_invocation="$("$docker_command" inspect --format '{{index .Config.Labels "shulker.seafile.restore-invocation"}}' "$name" 2>/dev/null || true)"
            if [ "$owner" = "$restore_project" ] && [ "$container_invocation" = "$invocation" ]; then
              "$docker_command" rm -f "$name" >/dev/null 2>&1 || cleanup_failed=1
            else
              cleanup_failed=1
            fi
          fi
        done
        if "$docker_command" network inspect "$restore_network" >/dev/null 2>&1; then
          owner="$("$docker_command" network inspect --format '{{index .Labels "shulker.seafile.restore-invocation"}}' "$restore_network" 2>/dev/null || true)"
          if [ "$owner" = "$invocation" ]; then
            "$docker_command" network rm "$restore_network" >/dev/null 2>&1 || cleanup_failed=1
          else
            cleanup_failed=1
          fi
        fi
        if [ "$cleanup_failed" -eq 0 ]; then
          [ "$target_prepared" -eq 0 ] || find "$target" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
          find "$runtime" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
          [ "$runtime_created" -eq 0 ] || rmdir "$runtime" 2>/dev/null || true
        else
          echo "Seafile restore rollback is incomplete; retry seafile-restore-teardown with $runtime" >&2
        fi
      fi
      exit "$status"
    }
    trap rollback_prepare EXIT
    trap 'exit 75' HUP INT TERM

    available_ram_kib="$($free_command --kibi | awk '/^Mem:/ {print $7}')"
    swap_kib="$($free_command --kibi | awk '/^Swap:/ {print $2}')"
    [ "$available_ram_kib" -ge 10485760 ] || fail_restore "less than 10 GiB available RAM"
    [ "$swap_kib" -ge 4194304 ] || fail_restore "less than 4 GiB swap"
    target_bytes="$(( $($df_command --output=avail -B1 "$target" | tail -1) ))"
    target_inodes="$(( $($df_command --output=iavail "$target" | tail -1) ))"
    [ "$target_bytes" -ge 53687091200 ] && [ "$target_inodes" -ge 100000 ] \
      || fail_restore "target bytes or inodes are insufficient"
    docker_root="$("$docker_command" info --format '{{.DockerRootDir}}')"
    docker_bytes="$(( $($df_command --output=avail -B1 "$docker_root" | tail -1) ))"
    [ "$docker_bytes" -ge 12884901888 ] || fail_restore "Docker storage has less than 12 GiB"
    zfs_available="$($zfs_command get -Hp -o value available ${lib.escapeShellArg cfg.dataset})"
    [ "$zfs_available" -ge 53687091200 ] || fail_restore "ZFS pool and COW reserve are insufficient"
    "$docker_command" network inspect "$restore_network" >/dev/null 2>&1 \
      && fail_restore "restore network collision"
    for name in "''${restore_names[@]}"; do
      "$docker_command" inspect "$name" >/dev/null 2>&1 && fail_restore "restore container collision"
    done

    "$install_command" -d -m 0700 "$runtime/host" "$runtime/app" "$runtime/metadata" "$runtime/ca" "$runtime/proxy"
    "$install_command" -d -m 0750 "$target/shared" "$target/search" "$target/onlyoffice" \
      "$target/onlyoffice/logs" "$target/onlyoffice/data" "$target/onlyoffice/lib"
    "$install_command" -d -m 0700 "$target/database" "$target/backups" "$target/control"
    "$install_command" -d -m 0750 "$target/shared/seafile/conf"
    target_prepared=1

    source_environment="$runtime/source.environment"
    emit_restore_environment() { printf '%s=%s\n' "$1" "$2"; }
    {
      emit_restore_environment INIT_SEAFILE_MYSQL_ROOT_PASSWORD "$(openssl rand -hex 32)"
      emit_restore_environment SEAFILE_MYSQL_DB_PASSWORD "$(openssl rand -hex 32)"
      emit_restore_environment REDIS_PASSWORD "$(openssl rand -hex 32)"
      emit_restore_environment JWT_PRIVATE_KEY "$(openssl rand -hex 32)"
      emit_restore_environment SEAHUB_SECRET_KEY "$(openssl rand -hex 32)"
      emit_restore_environment INIT_SEAFILE_ADMIN_EMAIL restore-admin@restore.invalid
      emit_restore_environment INIT_SEAFILE_ADMIN_PASSWORD "$(openssl rand -hex 32)"
      emit_restore_environment INIT_SS_ADMIN_USER restore-seasearch
      emit_restore_environment INIT_SS_ADMIN_PASSWORD "$(openssl rand -hex 32)"
      emit_restore_environment SEAFILE_OAUTH_CLIENT_ID restore-disabled
      emit_restore_environment SEAFILE_OAUTH_CLIENT_SECRET "$(openssl rand -hex 32)"
      emit_restore_environment ONLYOFFICE_JWT_SECRET "$(openssl rand -hex 32)"
    } >"$source_environment"
    chmod 0600 "$source_environment"
    "$render_command" --source "$source_environment" --host-dir "$runtime/host" \
      --app-dir "$runtime/app" --metadata-dir "$runtime/metadata" \
      --state-dir "$target" --lock-file "$runtime/maintenance.lock" --lock-timeout 0 \
      --container-project "$restore_project"
    compose_environment="$runtime/compose.environment"
    {
      printf 'SEAFILE_RESTORE_TARGET=%s\nSEAFILE_RESTORE_RUNTIME=%s\n' "$target" "$runtime"
      cat "$runtime/host/compose.environment"
    } >"$compose_environment"
    chmod 0600 "$compose_environment"

    chmod 0600 "$runtime/app/seafile.env" "$runtime/app/seahub_settings.py"
    sed -i -E 's|^SEAFILE_SERVER_HOSTNAME=.*$|SEAFILE_SERVER_HOSTNAME=files.restore.invalid:24239|' \
      "$runtime/app/seafile.env"
    sed -i -E \
      -e 's|^ENABLE_OAUTH = True$|ENABLE_OAUTH = False|' \
      -e 's|^OAUTH_CREATE_UNKNOWN_USER = True$|OAUTH_CREATE_UNKNOWN_USER = False|' \
      -e 's|^ONLYOFFICE_APIJS_URL = .*$|ONLYOFFICE_APIJS_URL = "https://office.restore.invalid:24240/web-apps/apps/api/documents/api.js"|' \
      -e 's|^SERVICE_URL = .*$|SERVICE_URL = "http://seafile-restore-seafile:80"|' \
      "$runtime/app/seahub_settings.py"
    chmod 0400 "$runtime/app/seafile.env" "$runtime/app/seahub_settings.py"
    for mapping in .env:seafile.env seahub_settings.py:seahub_settings.py \
      seafevents.conf:seafevents.conf seafile.conf:seafile.conf seafdav.conf:seafdav.conf; do
      name="''${mapping%%:*}"
      source_name="''${mapping#*:}"
      ln -s "$runtime/app/$source_name" "$target/shared/seafile/conf/$name"
    done

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
    chmod 0600 "$runtime/ca"/*.key "$source_environment" "$compose_environment"
    cat >"$runtime/proxy/nginx.conf" <<'NGINX'
    events {}
    http {
      map $http_upgrade $connection_upgrade { default upgrade; "" close; }
      server {
        listen 443 ssl;
        server_name files.restore.invalid;
        ssl_certificate /run/seafile-restore-ca/files.restore.invalid.crt;
        ssl_certificate_key /run/seafile-restore-ca/files.restore.invalid.key;
        location / { proxy_set_header Host $host; proxy_set_header X-Forwarded-Proto https; proxy_pass http://seafile-restore-seafile:80; }
      }
      server {
        listen 444 ssl;
        server_name office.restore.invalid;
        ssl_certificate /run/seafile-restore-ca/office.restore.invalid.crt;
        ssl_certificate_key /run/seafile-restore-ca/office.restore.invalid.key;
        location / { proxy_set_header Host $host; proxy_set_header X-Forwarded-Proto https; proxy_pass http://seafile-restore-onlyoffice:80; }
      }
      server {
        listen 445 ssl;
        server_name files.restore.invalid;
        ssl_certificate /run/seafile-restore-ca/files.restore.invalid.crt;
        ssl_certificate_key /run/seafile-restore-ca/files.restore.invalid.key;
        location /notification/ {
          proxy_http_version 1.1;
          proxy_set_header Upgrade $http_upgrade;
          proxy_set_header Connection $connection_upgrade;
          proxy_pass http://seafile-restore-notification:8083/;
        }
      }
    }
    NGINX
    chmod 0600 "$runtime/proxy/nginx.conf"

    provisional="$runtime/.rehearsal-session.$invocation"
    {
      printf 'invocation=%s\ntarget=%s\nruntime=%s\nproject=%s\nnetwork=%s\nnetwork_id=%s\n' \
        "$invocation" "$target" "$runtime" "$restore_project" "$restore_network" "$restore_network"
      printf 'credential_file=%s\ncompose_environment=%s\n' "$source_environment" "$compose_environment"
      printf 'container_database=seafile-restore-mariadb\ncontainer_redis=seafile-restore-redis\n'
      printf 'container_seafile=seafile-restore-seafile\ncontainer_seasearch=seafile-restore-seasearch\n'
      printf 'container_notification=seafile-restore-notification\ncontainer_metadata=seafile-restore-metadata\n'
      printf 'container_onlyoffice=seafile-restore-onlyoffice\ncontainer_proxy=seafile-restore-proxy\n'
    } >"$provisional"
    chmod 0600 "$provisional"
    mv -T -- "$provisional" "$session"

    "$docker_command" network create --internal \
      --label "com.docker.compose.project=$restore_project" \
      --label "com.docker.compose.network=$restore_network" \
      --label "shulker.seafile.restore-invocation=$invocation" "$restore_network" >/dev/null
    network_id="$("$docker_command" network inspect --format '{{.Id}}' "$restore_network")"
    compose_restore_bootstrap create
    services=(database redis seafile seasearch notification metadata onlyoffice proxy)
    app_ids=()
    for service in "''${services[@]}"; do
      id="$(compose_restore_bootstrap ps -q "$service")"
      [ -n "$id" ] || fail_restore "missing restore container ID"
      app_ids+=("$id")
    done
    session_temporary="$runtime/.rehearsal-session.$invocation"
    {
      printf 'invocation=%s\ntarget=%s\nruntime=%s\nproject=%s\nnetwork=%s\nnetwork_id=%s\n' \
        "$invocation" "$target" "$runtime" "$restore_project" "$restore_network" "$network_id"
      printf 'credential_file=%s\ncompose_environment=%s\n' "$source_environment" "$compose_environment"
      for index in "''${!app_ids[@]}"; do
        printf 'container_%s=%s\n' "''${services[$index]}" "''${app_ids[$index]}"
      done
    } >"$session_temporary"
    chmod 0600 "$session_temporary"
    mv -T -- "$session_temporary" "$session"
    session_written=1
    trap - EXIT HUP INT TERM
    echo "Restore rehearsal prepared; extract one selected archive before verification"
  '';

  restoreVerifyScript = ''
    ${restoreCommonScript}
    runtime=
    backup_set=
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --runtime-dir) runtime="$2"; shift 2 ;;
        --backup-set) backup_set="$2"; shift 2 ;;
        *) fail_restore "unexpected verify argument" ;;
      esac
    done
    [ -n "$runtime" ] && [[ "$backup_set" =~ ^seafile-[A-Za-z0-9._-]+$ ]] \
      || fail_restore "runtime directory and safe backup-set name are required"
    session="$runtime/rehearsal-session"
    [ -f "$session" ] && [ ! -L "$session" ] && [ "$(stat --format '%a' "$session")" = 600 ] \
      || fail_restore "owned rehearsal session is missing"
    target="$(restore_field "$session" target)"
    restore_invocation="$(restore_field "$session" invocation)"
    [[ "$restore_invocation" =~ ^[a-f0-9-]+$ ]] || fail_restore "restore invocation is malformed"
    case "$target" in "$production_state"|"$production_state"/*) fail_restore "production target is forbidden" ;; esac
    source_environment="$(restore_field "$session" credential_file)"
    compose_environment="$(restore_field "$session" compose_environment)"
    [ "$source_environment" = "$runtime/source.environment" ] \
      && [ "$compose_environment" = "$runtime/compose.environment" ] \
      || fail_restore "foreign restore credential source"
    [ -f "$source_environment" ] && [ ! -L "$source_environment" ] \
      && [ "$(stat --format '%a' "$source_environment")" = 600 ] \
      || fail_restore "protected restore credentials are missing"

    candidate="$target/backups/$backup_set"
    [ -d "$candidate" ] && [ ! -L "$candidate" ] || fail_restore "selected backup set is missing"
    manifest="$candidate/manifest.json"
    expected_versions=${lib.escapeShellArg (builtins.toJSON cfg.releaseVersions)}
    jq -e --argjson expected "$expected_versions" \
      '.release_versions == $expected
       and .schema_format == "mariadb-sql-v1"
       and .transaction_kind == "writers_quiesced=true"
       and ([.databases[].name] | sort) == ["ccnet_db","seafile_db","seahub_db"]
       and ([.databases[].file] | sort) == ["ccnet_db.sql","seafile_db.sql","seahub_db.sql"]
       and (.databases | length) == 3' "$manifest" >/dev/null \
      || fail_restore "backup manifest or release matrix is incompatible"
    for database in ccnet_db seafile_db seahub_db; do
      dump="$candidate/$database.sql"
      expected_size="$(jq -er --arg name "$database" '.databases[] | select(.name == $name) | .size_bytes' "$manifest")"
      expected_checksum="$(jq -er --arg name "$database" '.databases[] | select(.name == $name) | .sha256' "$manifest")"
      [ -f "$dump" ] && [ ! -L "$dump" ] && [ "$(stat --format '%s' "$dump")" = "$expected_size" ] \
        && [ "$(sha256sum "$dump" | cut -d' ' -f1)" = "$expected_checksum" ] \
        || fail_restore "$database dump checksum or size is invalid"
    done
    for mapping in .env:seafile.env seahub_settings.py:seahub_settings.py \
      seafevents.conf:seafevents.conf seafile.conf:seafile.conf seafdav.conf:seafdav.conf; do
      name="''${mapping%%:*}"
      source_name="''${mapping#*:}"
      [ -L "$target/shared/seafile/conf/$name" ] \
        && [ "$(readlink "$target/shared/seafile/conf/$name")" = "$runtime/app/$source_name" ] \
        || fail_restore "restore runtime configuration link is missing"
    done
    for service in database redis seafile seasearch notification metadata onlyoffice proxy; do
      id="$(restore_field "$session" "container_$service")"
      if [ -z "$id" ] || ! "$docker_command" inspect "$id" >/dev/null; then
        fail_restore "recorded restore container is missing"
      fi
      [ "$("$docker_command" inspect --format '{{index .Config.Labels "com.docker.compose.project"}}' "$id")" = "$restore_project" ] \
        || fail_restore "recorded restore container is foreign"
      [ "$("$docker_command" inspect --format '{{index .Config.Labels "shulker.seafile.restore-invocation"}}' "$id")" = "$restore_invocation" ] \
        || fail_restore "recorded restore container belongs to another invocation"
      [ "$("$docker_command" inspect --format '{{.State.Running}}' "$id")" = false ] \
        || fail_restore "restore verification requires every recorded container to be stopped"
    done

    compose_restore_bootstrap up --detach --no-deps --wait --wait-timeout 1800 database redis
    secret_value() {
      local key="$1" count
      count="$(grep -c "^$key=" "$source_environment" || true)"
      [ "$count" -eq 1 ] || fail_restore "restore credential schema is incomplete"
      sed -n "s/^$key=//p" "$source_environment"
    }
    MYSQL_PWD="$(secret_value INIT_SEAFILE_MYSQL_ROOT_PASSWORD)"
    database_password="$(secret_value SEAFILE_MYSQL_DB_PASSWORD)"
    export MYSQL_PWD
    database_id="$(restore_field "$session" container_database)"
    for database in ccnet_db seafile_db seahub_db; do
      "$timeout_command" 3600 "$docker_command" exec -i --env MYSQL_PWD "$database_id" \
        mariadb --user root <"$candidate/$database.sql"
    done
    printf "CREATE USER IF NOT EXISTS 'seafile'@'%%' IDENTIFIED BY '%s'; GRANT ALL ON ccnet_db.* TO 'seafile'@'%%'; GRANT ALL ON seafile_db.* TO 'seafile'@'%%'; GRANT ALL ON seahub_db.* TO 'seafile'@'%%'; FLUSH PRIVILEGES;\n" \
      "$database_password" | "$docker_command" exec -i --env MYSQL_PWD "$database_id" mariadb --user=root
    unset MYSQL_PWD database_password

    compose_restore_bootstrap up --detach --no-recreate --wait --wait-timeout 2100
    seafile_id="$(restore_field "$session" container_seafile)"
    native_email="$("$docker_command" exec -i \
      --env SEAFILE_RESTORE_NATIVE_MODE=identify "$seafile_id" \
      /opt/seafile/seafile-server-latest/seahub.sh python-env python - \
      <${restoreIdentifyNativeAdmin})"
    [[ "$native_email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]] \
      || fail_restore "restored native administrator could not be identified safely"
    restore_password="$(secret_value INIT_SEAFILE_ADMIN_PASSWORD)"
    RESTORE_NATIVE_EMAIL="$native_email"
    RESTORE_PASSWORD="$restore_password"
    export RESTORE_NATIVE_EMAIL RESTORE_PASSWORD
    "$docker_command" exec -i --env RESTORE_NATIVE_EMAIL --env RESTORE_PASSWORD \
      --env SEAFILE_RESTORE_NATIVE_MODE=reset "$seafile_id" \
      /opt/seafile/seafile-server-latest/seahub.sh python-env python - \
      <${restoreResetNativeAdmin} >/dev/null
    "$docker_command" exec -i --env RESTORE_NATIVE_EMAIL --env RESTORE_PASSWORD \
      --env SEAFILE_RESTORE_NATIVE_MODE=verify "$seafile_id" \
      /opt/seafile/seafile-server-latest/seahub.sh python-env python - \
      <${restoreVerifyNativeAdmin} >/dev/null
    unset RESTORE_NATIVE_EMAIL RESTORE_PASSWORD restore_password native_email

    "$docker_command" exec "$seafile_id" /opt/seafile/seafile-server-latest/seaf-fsck.sh --readonly
    "$docker_command" exec "$(restore_field "$session" container_metadata)" test -r /run/seafile/seafile.conf
    "$curl_command" --fail --cacert "$runtime/ca/ca.crt" --resolve files.restore.invalid:24239:127.0.0.1 \
      https://files.restore.invalid:24239/ >/dev/null
    "$curl_command" --fail --cacert "$runtime/ca/ca.crt" --resolve files.restore.invalid:24241:127.0.0.1 \
      https://files.restore.invalid:24241/notification/ping >/dev/null
    [ "$("$curl_command" --fail --silent --cacert "$runtime/ca/ca.crt" \
      --resolve office.restore.invalid:24240:127.0.0.1 \
      https://office.restore.invalid:24240/healthcheck)" = true ] \
      || fail_restore "OnlyOffice restore health check failed"
    echo "Compatible releases, three database checksums/imports, restore-only native recovery, read-only fsck, Metadata config, and isolated HTTPS health verified"
  '';

  restoreTeardownScript = ''
    ${restoreCommonScript}
    runtime=
    while [ "$#" -gt 0 ]; do case "$1" in --runtime-dir) runtime="$2"; shift 2 ;; *) fail_restore "unexpected teardown argument" ;; esac; done
    session="$runtime/rehearsal-session"
    [ -e "$session" ] || exit 0
    [ -f "$session" ] && [ ! -L "$session" ] || fail_restore "foreign rehearsal session"
    target="$(restore_field "$session" target)"
    invocation="$(restore_field "$session" invocation)"
    restore_invocation="$invocation"
    [[ "$invocation" =~ ^[a-f0-9-]+$ ]] || fail_restore "restore invocation is malformed"
    case "$target" in "$production_state"|"$production_state"/*) fail_restore "production target is forbidden" ;; esac
    for service in database redis seafile seasearch notification metadata onlyoffice proxy; do
      id="$(restore_field "$session" "container_$service")"
      if "$docker_command" inspect "$id" >/dev/null 2>&1; then
        [ "$("$docker_command" inspect --format '{{index .Config.Labels "com.docker.compose.project"}}' "$id")" = "$restore_project" ] \
          || fail_restore "recorded restore container is foreign"
        [ "$("$docker_command" inspect --format '{{index .Config.Labels "shulker.seafile.restore-invocation"}}' "$id")" = "$invocation" ] \
          || fail_restore "recorded restore container belongs to another invocation"
        "$docker_command" rm -f "$id" >/dev/null || fail_restore "restore container removal failed"
      fi
    done
    network_id="$(restore_field "$session" network_id)"
    if "$docker_command" network inspect "$network_id" >/dev/null 2>&1; then
      [ "$("$docker_command" network inspect --format '{{index .Labels "shulker.seafile.restore-invocation"}}' "$network_id")" = "$invocation" ] \
        || fail_restore "recorded restore network is foreign"
      "$docker_command" network rm "$network_id" >/dev/null || fail_restore "restore network removal failed"
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
        pkgs.procps
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
  restorePrepare = mkBackupPackage "seafile-restore-prepare" restorePrepareScript [ ];
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
      Restore verification checks the selected release matrix, dump checksums and imports before application health.
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
    restoreIdentifyNativeAdminFile = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      internal = true;
    };
    restoreIdentifyNativeAdminScript = lib.mkOption {
      type = lib.types.lines;
      readOnly = true;
      internal = true;
    };
    restoreResetNativeAdminFile = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      internal = true;
    };
    restoreResetNativeAdminScript = lib.mkOption {
      type = lib.types.lines;
      readOnly = true;
      internal = true;
    };
    restoreVerifyNativeAdminFile = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      internal = true;
    };
    restoreVerifyNativeAdminScript = lib.mkOption {
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
      restoreIdentifyNativeAdminFile = restoreIdentifyNativeAdmin;
      inherit restoreIdentifyNativeAdminScript;
      restoreResetNativeAdminFile = restoreResetNativeAdmin;
      inherit restoreResetNativeAdminScript;
      restoreVerifyNativeAdminFile = restoreVerifyNativeAdmin;
      inherit restoreVerifyNativeAdminScript;
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
