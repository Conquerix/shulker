{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.shulker.system.modules.seafile;
  secret = config.services.onepassword-secrets.secrets.seafileEnv;
  composeFactory = import ../../../../lib/seafile-compose.nix { inherit pkgs; };
  stack = composeFactory {
    projectName = "seafile";
    containerNames = {
      seafile = "seafile";
      database = "seafile-mariadb";
      redis = "seafile-redis";
      seasearch = "seafile-seasearch";
      notification = "seafile-notification";
      metadata = "seafile-metadata";
      onlyoffice = "seafile-onlyoffice";
    };
    networkName = "seafile-net";
    stateDir = cfg.stateDir;
    appRuntimeDir = "/run/seafile-app";
    metadataRuntimeDir = "/run/seafile-metadata";
    bindAddress = cfg.bindAddress;
    ports = {
      seafile = cfg.port;
      onlyoffice = cfg.onlyOfficePort;
      notification = cfg.notificationPort;
    };
    urls = {
      hostname = lib.removePrefix "https://" cfg.publicUrl;
      notificationPublic = cfg.notificationPublicUrl;
      notificationInternal = cfg.notificationInternalUrl;
    };
    images = {
      database = cfg.databaseImage;
      metadata = cfg.metadataImage;
      notification = cfg.notificationImage;
      onlyoffice = cfg.onlyOfficeImage;
      redis = cfg.redisImage;
      seafile = cfg.seafileImage;
      seasearch = cfg.seasearchImage;
    };
    metadata = {
      fileCountLimit = cfg.metadataFileCountLimit;
      cacheSize = cfg.metadataCacheSize;
      checkUpdateInterval = cfg.metadataCheckUpdateInterval;
    };
  };
  composeStartScript = ''
    set -eEuo pipefail
    umask 077

    action="''${1:-}"
    state_dir="''${SEAFILE_STATE_DIR:-${cfg.stateDir}}"
    host_dir="''${SEAFILE_HOST_DIR:-/run/seafile-host}"
    app_dir="''${SEAFILE_APP_DIR:-/run/seafile-app}"
    lock_file="''${SEAFILE_MAINTENANCE_LOCK:-/run/lock/seafile-maintenance.lock}"
    lock_timeout="''${SEAFILE_LOCK_TIMEOUT:-1800}"
    wait_timeout="''${SEAFILE_WAIT_TIMEOUT:-1800}"
    stop_timeout="''${SEAFILE_STOP_TIMEOUT:-120}"
    log_capture_max_bytes="''${SEAFILE_LOG_CAPTURE_MAX_BYTES:-16777215}"
    docker_command="''${SEAFILE_DOCKER_COMMAND:-docker}"
    systemctl_command="''${SEAFILE_SYSTEMCTL_COMMAND:-systemctl}"
    journalctl_command="''${SEAFILE_JOURNALCTL_COMMAND:-journalctl}"
    reconcile_command="''${SEAFILE_RECONCILE_COMMAND:-seafile-reconcile-runtime-config}"
    compose_file="''${SEAFILE_COMPOSE_FILE:-${stack.composeFile}}"
    bootstrap_compose_file="''${SEAFILE_BOOTSTRAP_COMPOSE_FILE:-${stack.bootstrapComposeFile}}"
    expected_owner="''${SEAFILE_EXPECTED_OWNER:-0:0}"
    expected_names=(
      seafile
      seafile-mariadb
      seafile-metadata
      seafile-notification
      seafile-onlyoffice
      seafile-redis
      seafile-seasearch
    )
    expected_services=(
      seafile
      database
      metadata
      notification
      onlyoffice
      redis
      seasearch
    )

    fail_stack() {
      echo "Seafile stack orchestration failed: $1" >&2
      return 65
    }

    compose_established() {
      "$docker_command" compose --project-name seafile --file "$compose_file" \
        --env-file "$host_dir/environment" "$@"
    }

    compose_bootstrap() {
      "$docker_command" compose --project-name seafile --file "$compose_file" \
        --file "$bootstrap_compose_file" \
        --env-file "$host_dir/bootstrap.environment" "$@"
    }

    project_names() {
      "$docker_command" ps --all \
        --filter label=com.docker.compose.project=seafile \
        --format '{{.Names}}' | sed '/^$/d' | LC_ALL=C sort
    }

    refuse_unknown_containers() {
      local name known
      while IFS= read -r name; do
        [ -n "$name" ] || continue
        known=0
        for expected in "''${expected_names[@]}"; do
          [ "$name" = "$expected" ] && known=1
        done
        [ "$known" -eq 1 ] || fail_stack "unknown container carries the seafile project label"
      done < <(project_names)
    }

    container_running() {
      [ -n "$("$docker_command" ps --quiet --filter "name=^/$1$")" ]
    }

    stop_known_gracefully() {
      local deadline name running
      [ "$#" -gt 0 ] || return 0
      running=()
      for name in "$@"; do
        if container_running "$name"; then
          running+=("$name")
          "$docker_command" kill --signal TERM "$name" >/dev/null
        fi
      done
      deadline=$((SECONDS + stop_timeout))
      while [ "''${#running[@]}" -gt 0 ]; do
        remaining=()
        for name in "''${running[@]}"; do
          container_running "$name" && remaining+=("$name")
        done
        running=("''${remaining[@]}")
        [ "''${#running[@]}" -eq 0 ] && return 0
        [ "$SECONDS" -lt "$deadline" ] \
          || fail_stack "containers did not stop after TERM within the bounded timeout"
        sleep 1
      done
    }

    read_environment_value() {
      local key="$1" file="$2" line value=""
      while IFS= read -r line || [ -n "$line" ]; do
        if [ "''${line%%=*}" = "$key" ]; then
          value="''${line#*=}"
          break
        fi
      done <"$file"
      [ -n "$value" ] || fail_stack "protected environment is missing a required value"
      printf '%s' "$value"
    }

    validate_admin_residue() {
      local admin_file email password expected
      admin_file="$state_dir/shared/seafile/conf/admin.txt"
      [ -e "$admin_file" ] || [ -L "$admin_file" ] || return 0
      [ -f "$admin_file" ] && [ ! -L "$admin_file" ] \
        || fail_stack "admin.txt crash residue is not a regular file"
      [ "$(stat -c '%u:%g' -- "$admin_file")" = "$expected_owner" ] \
        || fail_stack "admin.txt crash residue has an unsafe owner"
      [ "$(stat -c '%a' -- "$admin_file")" = 600 ] \
        || fail_stack "admin.txt crash residue has an unsafe mode"
      email="$(read_environment_value INIT_SEAFILE_ADMIN_EMAIL "$host_dir/environment")"
      password="$(read_environment_value INIT_SEAFILE_ADMIN_PASSWORD "$host_dir/environment")"
      expected="$(printf '{\"email\": \"%s\", \"password\": \"%s\"}' "$email" "$password")"
      printf '%s' "$expected" | cmp --silent - "$admin_file" \
        || fail_stack "admin.txt crash residue does not match the protected native administrator"
      rm -f -- "$admin_file"
    }

    reconcile_runtime() {
      SEAFILE_MAINTENANCE_LOCK_FD=9 \
        SEAFILE_ORCHESTRATION_STOPPED=1 \
        "$reconcile_command" \
          --source "$host_dir/bootstrap.environment" \
          --app-dir "$app_dir" \
          --state-dir "$state_dir" \
          --container-config-dir /run/seafile \
          --lock-file "$lock_file" \
          --lock-timeout "$lock_timeout" \
          --wait-timeout "$wait_timeout"
    }

    wait_for_bootstrap() {
      local deadline status
      deadline=$((SECONDS + wait_timeout))
      while :; do
        status="$("$docker_command" inspect --format '{{.State.Health.Status}}' seafile 2>/dev/null || true)"
        if [ "$status" = healthy ] \
          && [ -f "$state_dir/shared/seafile/seafile-data/current_version" ]; then
          return 0
        fi
        [ "$SECONDS" -lt "$deadline" ] || fail_stack "fresh Seafile bootstrap did not become healthy"
        sleep 1
      done
    }

    verify_exact_stack() {
      local actual expected name keys forbidden
      actual="$(project_names)"
      expected="$(printf '%s\n' "''${expected_names[@]}" | LC_ALL=C sort)"
      [ "$actual" = "$expected" ] || fail_stack "final stack does not contain exactly seven intended containers"
      for name in "''${expected_names[@]}"; do
        [ "$("$docker_command" inspect --format '{{.State.Running}}' "$name")" = true ] \
          || fail_stack "an intended container is not running"
        keys="$("$docker_command" inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$name" \
          | cut -d= -f1)"
        for forbidden in INIT_SEAFILE_MYSQL_ROOT_PASSWORD INIT_SS_ADMIN_USER INIT_SS_ADMIN_PASSWORD; do
          ! grep -F -x "$forbidden" <<<"$keys" >/dev/null \
            || fail_stack "an established container retains a removable initialization key"
        done
        if [ "$name" != seafile ]; then
          for forbidden in INIT_SEAFILE_ADMIN_EMAIL INIT_SEAFILE_ADMIN_PASSWORD; do
            ! grep -F -x "$forbidden" <<<"$keys" >/dev/null \
              || fail_stack "a non-Seafile container received a native administrator key"
          done
        fi
      done
    }

    verify_controlled_symlinks() {
      local name path
      for name in .env seahub_settings.py seafevents.conf seafile.conf seafdav.conf; do
        path="$state_dir/shared/seafile/conf/$name"
        [ -L "$path" ] || fail_stack "a controlled runtime configuration symlink is missing"
      done
      [ ! -e "$state_dir/shared/seafile/conf/admin.txt" ] \
        || fail_stack "admin.txt remains after startup"
    }

    scan_sensitive_output() (
      local patterns docker_output journal_output line value candidate
      local log_tree entry_count oversized_count captured_size
      case "$log_capture_max_bytes" in
        "" | *[!0-9]*) fail_stack "log capture bound is invalid" ;;
      esac
      [ "$log_capture_max_bytes" -gt 0 ] || fail_stack "log capture bound is invalid"
      patterns="$(mktemp "$host_dir/.seafile-scan-patterns.XXXXXX")"
      docker_output="$(mktemp "$host_dir/.seafile-docker-logs.XXXXXX")"
      journal_output="$(mktemp "$host_dir/.seafile-journal.XXXXXX")"
      chmod 0600 "$patterns" "$docker_output" "$journal_output"
      trap 'rm -f -- "$patterns" "$docker_output" "$journal_output"' EXIT
      while IFS= read -r line || [ -n "$line" ]; do
        value="''${line#*=}"
        [ -n "$value" ] && printf '%s\n' "$value" >>"$patterns"
      done <"$host_dir/bootstrap.environment"
      printf '%s:%s' \
        "$(read_environment_value INIT_SS_ADMIN_USER "$host_dir/bootstrap.environment")" \
        "$(read_environment_value INIT_SS_ADMIN_PASSWORD "$host_dir/bootstrap.environment")" \
        | base64 | tr -d '\n' >>"$patterns"
      printf '\n' >>"$patterns"
      "$docker_command" logs seafile >"$docker_output" 2>&1 \
        || fail_stack "Docker log output could not be captured"
      captured_size="$(wc -c <"$docker_output")"
      [ "$captured_size" -le "$log_capture_max_bytes" ] \
        || fail_stack "Docker log output exceeded its capture bound"
      if grep -F -q -f "$patterns" -- "$docker_output"; then
        fail_stack "sensitive material was detected in Seafile container logs"
      fi
      "$journalctl_command" --unit seafile-compose.service --no-pager \
        >"$journal_output" 2>&1 \
        || fail_stack "Compose unit journal output could not be captured"
      captured_size="$(wc -c <"$journal_output")"
      [ "$captured_size" -le "$log_capture_max_bytes" ] \
        || fail_stack "Compose unit journal output exceeded its capture bound"
      if grep -F -q -f "$patterns" -- "$journal_output"; then
        fail_stack "sensitive material was detected in the Compose unit journal"
      fi
      for log_tree in "$state_dir/shared/logs" "$state_dir/shared/seafile/logs"; do
        [ -e "$log_tree" ] || continue
        [ -d "$log_tree" ] && [ ! -L "$log_tree" ] \
          || fail_stack "persistent log tree is unsafe"
        entry_count="$(find "$log_tree" -mindepth 1 -printf . | wc -c)"
        [ "$entry_count" -le 10000 ] || fail_stack "persistent log tree exceeds its entry bound"
        oversized_count="$(find "$log_tree" -type f -size +16777215c -printf . | wc -c)"
        [ "$oversized_count" -eq 0 ] || fail_stack "persistent log tree contains an oversized file"
        while IFS= read -r -d "" candidate; do
          if grep -F -q -f "$patterns" -- "$candidate"; then
            fail_stack "sensitive material was detected in persistent logs"
          fi
        done < <(find "$log_tree" -type f -print0)
      done
    )

    run_start() {
      local fresh=0 index status
      local running_services_before=()
      refuse_unknown_containers
      for index in "''${!expected_names[@]}"; do
        if container_running "''${expected_names[$index]}"; then
          running_services_before+=("''${expected_services[$index]}")
        fi
      done
      recover_owned_on_failure() {
        status=$?
        trap - ERR
        if ! stop_known_gracefully "''${expected_names[@]}"; then
          echo "Seafile stack orchestration failed: failure recovery could not stop the attempted stack" >&2
          exit 70
        fi
        if [ "''${#running_services_before[@]}" -gt 0 ] \
          && ! compose_established up --detach "''${running_services_before[@]}"; then
          echo "Seafile stack orchestration failed: failure recovery could not restore the entry stack" >&2
          exit 70
        fi
        exit "$status"
      }
      trap recover_owned_on_failure ERR
      validate_admin_residue
      if [ ! -f "$state_dir/shared/seafile/seafile-data/current_version" ]; then
        fresh=1
        compose_bootstrap up --detach database redis seafile
        wait_for_bootstrap
        stop_known_gracefully seafile seafile-mariadb seafile-redis
        reconcile_runtime
        compose_bootstrap up --detach --wait --wait-timeout "$wait_timeout" seasearch
        stop_known_gracefully seafile-seasearch
        compose_established up --detach --force-recreate database seasearch
      else
        stop_known_gracefully "''${expected_names[@]}"
        reconcile_runtime
      fi
      refuse_unknown_containers
      compose_established up --detach --wait --wait-timeout "$wait_timeout"
      verify_exact_stack
      verify_controlled_symlinks
      scan_sensitive_output
      [ "$fresh" -eq 0 ] || [ -f "$state_dir/shared/seafile/seafile-data/current_version" ] \
        || fail_stack "fresh-start marker disappeared"
      trap - ERR
    }

    run_stop() {
      refuse_unknown_containers
      stop_known_gracefully "''${expected_names[@]}"
    }

    run_recover() {
      local actual expected name healthy=1
      actual="$(project_names)"
      expected="$(printf '%s\n' "''${expected_names[@]}" | LC_ALL=C sort)"
      if [ "$actual" = "$expected" ]; then
        for name in "''${expected_names[@]}"; do
          [ "$("$docker_command" inspect --format '{{.State.Health.Status}}' "$name" 2>/dev/null || true)" = healthy ] \
            || { healthy=0; break; }
        done
        [ "$healthy" -eq 0 ] || return 0
      fi
      if "$systemctl_command" is-active --quiet seafile-compose.service; then
        "$systemctl_command" --no-block reload seafile-compose.service
      else
        "$systemctl_command" --no-block start seafile-compose.service
      fi
    }

    case "$action" in
      start | reload | stop)
        install -d -m 0755 "$(dirname "$lock_file")"
        exec 9>"$lock_file"
        flock -w "$lock_timeout" 9 || fail_stack "maintenance lock could not be acquired"
        case "$action" in
          start | reload) run_start ;;
          stop) run_stop ;;
        esac
        ;;
      recover)
        install -d -m 0755 "$(dirname "$lock_file")"
        exec 9>"$lock_file"
        flock -n 9 || exit 0
        flock -u 9
        exec 9>&-
        run_recover
        ;;
      *)
        echo "usage: seafile-compose-start {start|reload|stop|recover}" >&2
        exit 64
        ;;
    esac
  '';
  composeStart = pkgs.writeShellApplication {
    name = "seafile-compose-start";
    runtimeInputs = [
      cfg.reconcileRuntimeConfigPackage
      config.virtualisation.docker.package
      pkgs.coreutils
      pkgs.findutils
      pkgs.gnugrep
      pkgs.gnused
      pkgs.systemd
      pkgs.util-linux
    ];
    text = composeStartScript;
  };
  composeCommand = "${pkgs.docker-compose}/bin/docker-compose --project-name seafile";
  establishedCompose = "${composeCommand} --file ${stack.composeFile} --env-file /run/seafile-host/environment";
in
{
  options.shulker.system.modules.seafile = {
    composeConfig = lib.mkOption {
      type = lib.types.attrs;
      readOnly = true;
      internal = true;
      description = "Evaluated established-state Seafile Compose configuration.";
    };
    composeFile = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      internal = true;
      description = "Generated established-state Seafile Compose file.";
    };
    bootstrapComposeConfig = lib.mkOption {
      type = lib.types.attrs;
      readOnly = true;
      internal = true;
      description = "Minimal fresh-bootstrap Seafile Compose override.";
    };
    bootstrapComposeFile = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      internal = true;
      description = "Generated fresh-bootstrap Seafile Compose override file.";
    };
    redisStartScript = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      internal = true;
      description = "Rootless-argv Redis entrypoint used by the pinned Alpine image.";
    };
    redisStartScriptText = lib.mkOption {
      type = lib.types.lines;
      readOnly = true;
      internal = true;
      description = "Source for the rootless-argv Redis entrypoint.";
    };
    onlyOfficeConfig = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      internal = true;
      description = "Generated non-secret OnlyOffice local configuration.";
    };
    composeStartScript = lib.mkOption {
      type = lib.types.lines;
      readOnly = true;
      internal = true;
      description = "Guarded Seafile Compose lifecycle implementation.";
    };
    composeStartPackage = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      internal = true;
      description = "Packaged guarded Seafile Compose lifecycle helper.";
    };
  };

  config = lib.mkIf cfg.enable {
    shulker.system.modules.seafile = {
      inherit (stack)
        bootstrapComposeConfig
        bootstrapComposeFile
        composeConfig
        composeFile
        onlyOfficeConfig
        redisStartScript
        redisStartScriptText
        ;
      inherit composeStartScript;
      composeStartPackage = composeStart;
    };

    environment.systemPackages = [ composeStart ];

    systemd.services.seafile-image-pull = {
      description = "Pull Seafile container images serially";
      wants = [ "network-online.target" ];
      requires = [
        "seafile-state.service"
        "seafile-config.service"
        "docker.service"
      ];
      after = [
        "seafile-state.service"
        "seafile-config.service"
        "docker.service"
        "network-online.target"
      ];
      unitConfig.ConditionFileNotEmpty = secret.path;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Environment = [ "COMPOSE_PARALLEL_LIMIT=1" ];
        ExecStartPre = "${establishedCompose} config --quiet";
        ExecStart = "${establishedCompose} pull";
        TimeoutStartSec = 10800;
        UMask = "0077";
      };
    };

    systemd.services.seafile-compose = {
      description = "Guarded seven-service Seafile stack";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      requires = [
        "seafile-state.service"
        "seafile-config.service"
        "seafile-image-pull.service"
        "docker.service"
      ];
      after = [
        "seafile-state.service"
        "seafile-config.service"
        "seafile-image-pull.service"
        "docker.service"
        "network-online.target"
      ];
      unitConfig = {
        BindsTo = [ "docker.service" ];
        ConditionFileNotEmpty = secret.path;
      };
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${composeStart}/bin/seafile-compose-start start";
        ExecReload = "${composeStart}/bin/seafile-compose-start reload";
        ExecStop = "${composeStart}/bin/seafile-compose-start stop";
        TimeoutStartSec = 1920;
        TimeoutStopSec = 1920;
        RuntimeDirectoryPreserve = "yes";
        UMask = "0077";
      };
    };

    systemd.services.seafile-compose-recovery = {
      description = "Recover the Seafile stack through its guarded systemd lifecycle";
      after = [ "docker.service" ];
      unitConfig = {
        ConditionFileNotEmpty = secret.path;
        StartLimitIntervalSec = 600;
        StartLimitBurst = 3;
      };
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${composeStart}/bin/seafile-compose-start recover";
        TimeoutStartSec = 60;
      };
    };

    systemd.timers.seafile-compose-recovery = {
      description = "Check guarded Seafile stack recovery every two minutes";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2m";
        OnUnitActiveSec = "2m";
        Persistent = true;
        RandomizedDelaySec = "30s";
      };
    };
  };
}
