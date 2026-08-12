{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.shulker.system.modules.seafile;
  secret = config.services.onepassword-secrets.secrets.seafileEnv;
  requiredEnvironmentKeys = [
    "INIT_SEAFILE_MYSQL_ROOT_PASSWORD"
    "SEAFILE_MYSQL_DB_PASSWORD"
    "REDIS_PASSWORD"
    "JWT_PRIVATE_KEY"
    "SEAHUB_SECRET_KEY"
    "INIT_SEAFILE_ADMIN_EMAIL"
    "INIT_SEAFILE_ADMIN_PASSWORD"
    "INIT_SS_ADMIN_USER"
    "INIT_SS_ADMIN_PASSWORD"
    "SEAFILE_OAUTH_CLIENT_ID"
    "SEAFILE_OAUTH_CLIENT_SECRET"
    "ONLYOFFICE_JWT_SECRET"
  ];
  safePattern = "^[A-Za-z0-9._~!@%+,/:=-]+$";
  mysqlPattern = "^[A-Za-z0-9._~!@+,/:=-]+$";
  emailPattern = "^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$";
  rule = minLength: pattern: { inherit minLength pattern; };
  exactKeys = {
    INIT_SEAFILE_MYSQL_ROOT_PASSWORD = rule 32 safePattern;
    SEAFILE_MYSQL_DB_PASSWORD = rule 32 mysqlPattern;
    REDIS_PASSWORD = rule 32 safePattern;
    JWT_PRIVATE_KEY = rule 32 safePattern;
    SEAHUB_SECRET_KEY = rule 50 safePattern;
    INIT_SEAFILE_ADMIN_EMAIL = rule 1 emailPattern;
    INIT_SEAFILE_ADMIN_PASSWORD = rule 32 safePattern;
    INIT_SS_ADMIN_USER = rule 1 safePattern;
    INIT_SS_ADMIN_PASSWORD = rule 32 safePattern;
    SEAFILE_OAUTH_CLIENT_ID = rule 1 safePattern;
    SEAFILE_OAUTH_CLIENT_SECRET = rule 32 safePattern;
    ONLYOFFICE_JWT_SECRET = rule 32 safePattern;
  };
  seahubSettingsText = ''
    import os

    SECRET_KEY = os.environ["SEAHUB_SECRET_KEY"]
    JWT_PRIVATE_KEY = os.environ["JWT_PRIVATE_KEY"]
    TIME_ZONE = "Europe/Paris"
    DATABASES = {
        "default": {
            "ENGINE": "django.db.backends.mysql",
            "NAME": "seahub_db",
            "USER": "seafile",
            "PASSWORD": os.environ["SEAFILE_MYSQL_DB_PASSWORD"],
            "HOST": "database",
            "PORT": "3306",
            "OPTIONS": {"charset": "utf8mb4"},
        }
    }
    ENABLE_OAUTH = True
    OAUTH_CREATE_UNKNOWN_USER = True
    OAUTH_ACTIVATE_USER_AFTER_CREATION = True
    OAUTH_ENABLE_INSECURE_TRANSPORT = False
    OAUTH_PROVIDER = "pocket-id"
    OAUTH_CLIENT_ID = os.environ["SEAFILE_OAUTH_CLIENT_ID"]
    OAUTH_CLIENT_SECRET = os.environ["SEAFILE_OAUTH_CLIENT_SECRET"]
    OAUTH_REDIRECT_URL = "${cfg.oauthCallbackUrl}"
    OAUTH_AUTHORIZATION_URL = "${cfg.oidcIssuer}/authorize"
    OAUTH_TOKEN_URL = "${cfg.oidcIssuer}/api/oidc/token"
    OAUTH_USER_INFO_URL = "${cfg.oidcIssuer}/api/oidc/userinfo"
    OAUTH_SCOPE = ["openid", "profile", "email"]
    OAUTH_ATTRIBUTE_MAP = {
        "sub": (True, "uid"),
        "name": (False, "name"),
        "email": (False, "contact_email"),
    }
    CLIENT_SSO_VIA_LOCAL_BROWSER = True
    ENABLE_SSO_USER_CHANGE_PASSWORD = False
    ENABLE_SETTINGS_VIA_WEB = False
    ENABLE_METADATA_MANAGEMENT = True
    METADATA_SERVER_URL = "http://seafile-metadata:8084"
    SHARE_LINK_FORCE_USE_PASSWORD = ${if cfg.shareLinkForceUsePassword then "True" else "False"}
    SHARE_LINK_PASSWORD_MIN_LENGTH = ${toString cfg.shareLinkPasswordMinLength}
    SHARE_LINK_PASSWORD_STRENGTH_LEVEL = ${toString cfg.shareLinkPasswordStrengthLevel}
    SHARE_LINK_EXPIRE_DAYS_DEFAULT = ${toString cfg.shareLinkExpireDaysDefault}
    SHARE_LINK_EXPIRE_DAYS_MAX = ${toString cfg.shareLinkExpireDaysMax}
    UPLOAD_LINK_EXPIRE_DAYS_DEFAULT = ${toString cfg.uploadLinkExpireDaysDefault}
    UPLOAD_LINK_EXPIRE_DAYS_MAX = ${toString cfg.uploadLinkExpireDaysMax}
    SHARE_LINK_LOGIN_REQUIRED = ${if cfg.shareLinkLoginRequired then "True" else "False"}
    ENABLE_ONLYOFFICE = True
    ONLYOFFICE_APIJS_URL = "${cfg.onlyOfficeApiUrl}"
    ONLYOFFICE_JWT_ENABLED = True
    ONLYOFFICE_JWT_SECRET = os.environ["ONLYOFFICE_JWT_SECRET"]
    ONLYOFFICE_EDIT_FILE_EXTENSION = (${
      lib.concatMapStringsSep ", " (extension: ''"${extension}"'') cfg.editableExtensions
    })
    ENABLE_WIKI = False
    SERVICE_URL = "${cfg.publicUrl}"
  '';
  parseEnvironmentScript = ''
    set -euo pipefail

    if [ "$#" -ne 2 ]; then
      echo "usage: seafile-parse-environment SOURCE OUTPUT" >&2
      exit 64
    fi

    source_file="$1"
    output_file="$2"
    expected_owner="''${SEAFILE_EXPECTED_OWNER:-0:0}"
    safe_pattern='${safePattern}'
    mysql_pattern='${mysqlPattern}'
    email_pattern='${emailPattern}'
    required_keys=(
      ${lib.concatMapStringsSep "\n      " lib.escapeShellArg requiredEnvironmentKeys}
    )
    declare -A values=()

    fail_parse() {
      local key="''${1:-}"
      if [ -n "$key" ]; then
        echo "Seafile environment validation failed for key $key" >&2
      else
        echo "Seafile environment validation failed" >&2
      fi
      exit 65
    }

    [ -f "$source_file" ] && [ ! -L "$source_file" ] || fail_parse
    [ "$(stat -c '%u:%g' -- "$source_file")" = "$expected_owner" ] || fail_parse
    source_mode="$(stat -c '%a' -- "$source_file")"
    [ "$source_mode" = 400 ] || [ "$source_mode" = 600 ] || fail_parse
    [ "$(stat -c '%h' -- "$source_file")" = 1 ] || fail_parse
    cmp --silent -- "$source_file" <(tr -d '\000' <"$source_file") || fail_parse

    while IFS= read -r line || [ -n "$line" ]; do
      [ -n "$line" ] && [[ "$line" == *=* ]] || fail_parse
      key="''${line%%=*}"
      value="''${line#*=}"
      [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || fail_parse "$key"
      [ -z "''${values[$key]+present}" ] || fail_parse "$key"
      [ -n "$value" ] || fail_parse "$key"

      case "$key" in
        INIT_SEAFILE_MYSQL_ROOT_PASSWORD | REDIS_PASSWORD | JWT_PRIVATE_KEY | \
          INIT_SEAFILE_ADMIN_PASSWORD | INIT_SS_ADMIN_PASSWORD | \
          SEAFILE_OAUTH_CLIENT_SECRET | ONLYOFFICE_JWT_SECRET)
          [ "''${#value}" -ge 32 ] && [[ "$value" =~ $safe_pattern ]] || fail_parse "$key"
          ;;
        SEAFILE_MYSQL_DB_PASSWORD)
          [ "''${#value}" -ge 32 ] && [[ "$value" =~ $mysql_pattern ]] || fail_parse "$key"
          ;;
        SEAHUB_SECRET_KEY)
          [ "''${#value}" -ge 50 ] && [[ "$value" =~ $safe_pattern ]] || fail_parse "$key"
          ;;
        INIT_SEAFILE_ADMIN_EMAIL)
          [[ "$value" =~ $email_pattern ]] || fail_parse "$key"
          ;;
        INIT_SS_ADMIN_USER | SEAFILE_OAUTH_CLIENT_ID)
          [[ "$value" =~ $safe_pattern ]] || fail_parse "$key"
          ;;
        *) fail_parse "$key" ;;
      esac
      values["$key"]="$value"
    done <"$source_file"

    [ "''${#values[@]}" -eq "''${#required_keys[@]}" ] || fail_parse
    for key in "''${required_keys[@]}"; do
      [ -n "''${values[$key]+present}" ] || fail_parse "$key"
    done

    if [ -e "$output_file" ] || [ -L "$output_file" ]; then
      [ -f "$output_file" ] && [ ! -L "$output_file" ] \
        && [ "$(stat -c '%u:%g' -- "$output_file")" = "$expected_owner" ] \
        || fail_parse
      : >"$output_file"
      chmod 0600 "$output_file"
    else
      install -m 0600 /dev/null "$output_file"
    fi
    for key in "''${required_keys[@]}"; do
      printf '%s=%s\n' "$key" "''${values[$key]}" >>"$output_file"
    done
    chmod 0400 "$output_file"
  '';
  parseEnvironmentRuntimeInputs = [
    pkgs.coreutils
    pkgs.diffutils
  ];
  parseEnvironment = pkgs.writeShellApplication {
    name = "seafile-parse-environment";
    runtimeInputs = parseEnvironmentRuntimeInputs;
    text = parseEnvironmentScript;
  };
  renderRuntimeConfigScript = ''
        set -euo pipefail
        umask 077

        source_file=${lib.escapeShellArg secret.path}
        host_dir=/run/seafile-host
        app_dir=/run/seafile-app
        metadata_dir=/run/seafile-metadata
        state_dir=${lib.escapeShellArg cfg.stateDir}
        lock_file=/run/lock/seafile-maintenance.lock
        lock_timeout=1800
        container_project=seafile

        usage() {
          echo "usage: seafile-render-runtime-config [--source PATH --host-dir PATH --app-dir PATH --metadata-dir PATH --state-dir PATH --lock-file PATH --lock-timeout SECONDS --container-project NAME]" >&2
          exit 64
        }

        while [ "$#" -gt 0 ]; do
          case "$1" in
            --source) source_file="$2"; shift 2 ;;
            --host-dir) host_dir="$2"; shift 2 ;;
            --app-dir) app_dir="$2"; shift 2 ;;
            --metadata-dir) metadata_dir="$2"; shift 2 ;;
            --state-dir) state_dir="$2"; shift 2 ;;
            --lock-file) lock_file="$2"; shift 2 ;;
            --lock-timeout) lock_timeout="$2"; shift 2 ;;
            --container-project) container_project="$2"; shift 2 ;;
            *) usage ;;
          esac
        done

        fail_render() {
          echo "Seafile runtime configuration render failed: $1" >&2
          exit 65
        }

        [ -d "$state_dir" ] && [ ! -L "$state_dir" ] \
          || fail_render "state directory is unavailable"
        [[ "$container_project" =~ ^[a-z0-9][a-z0-9_.-]*$ ]] \
          || fail_render "container project is malformed"
        install -d -m 0755 "$(dirname "$lock_file")"

        inherited_fd="''${SEAFILE_MAINTENANCE_LOCK_FD:-}"
        if [ -n "$inherited_fd" ]; then
          [[ "$inherited_fd" =~ ^[0-9]+$ ]] \
            || fail_render "inherited maintenance lock proof is malformed"
          [ "''${SEAFILE_ORCHESTRATION_STOPPED:-0}" = 1 ] \
            || fail_render "inherited maintenance lock lacks stopped-orchestration proof"
          [ -e "/proc/$$/fd/$inherited_fd" ] \
            || fail_render "inherited maintenance lock descriptor is unavailable"
          [ "$(readlink -f "/proc/$$/fd/$inherited_fd")" = "$(readlink -f "$lock_file")" ] \
            || fail_render "inherited maintenance lock targets the wrong file"
        else
          exec 9>"$lock_file"
          flock -w "$lock_timeout" 9 \
            || fail_render "maintenance lock could not be acquired"
        fi

        docker_command="''${SEAFILE_DOCKER_COMMAND:-docker}"
        set +e
        live_containers="$($docker_command ps --quiet --filter "label=com.docker.compose.project=$container_project" 2>/dev/null)"
        docker_status=$?
        set -e
        [ "$docker_status" -eq 0 ] || fail_render "owned-container state could not be verified"
        [ -z "$live_containers" ] || fail_render "owned containers are still running"

        expected_owner="''${SEAFILE_EXPECTED_OWNER:-0:0}"
        prepare_directory() {
          local path="$1"
          local mode="$2"
          if [ ! -e "$path" ] && [ ! -L "$path" ]; then
            install -d -m "$mode" "$path"
          fi
          [ -d "$path" ] && [ ! -L "$path" ] || fail_render "runtime path is unsafe"
          [ "$(stat -c '%u:%g' -- "$path")" = "$expected_owner" ] \
            || fail_render "runtime path owner is unsafe"
          chmod "$mode" "$path"
        }

        prepare_directory "$host_dir" 0700
        prepare_directory "$app_dir" 0700
        prepare_directory "$metadata_dir" 0555

        reject_unexpected_paths() {
          local path="$1"
          shift
          local entry name allowed
          while IFS= read -r -d "" entry; do
            name="''${entry##*/}"
            allowed=0
            for expected in "$@"; do
              [ "$name" = "$expected" ] && allowed=1
            done
            [ "$allowed" -eq 1 ] || fail_render "runtime directory contains an unexpected output path"
          done < <(find "$path" -mindepth 1 -maxdepth 1 -print0)
        }

        reject_unexpected_paths "$host_dir" bootstrap.environment environment
        reject_unexpected_paths "$app_dir" \
          seafile.env seahub_settings.py seafevents.conf seafile.conf seafdav.conf
        reject_unexpected_paths "$metadata_dir" seafile.conf

        validate_existing_destination() {
          local path="$1"
          local expected_mode="$2"
          if [ -e "$path" ] || [ -L "$path" ]; then
            [ -f "$path" ] && [ ! -L "$path" ] \
              || fail_render "managed runtime destination is not a regular file"
            [ "$(stat -c '%u:%g' -- "$path")" = "$expected_owner" ] \
              || fail_render "managed runtime destination owner is unsafe"
            [ "$(stat -c '%a' -- "$path")" = "$expected_mode" ] \
              || fail_render "managed runtime destination mode is unsafe"
            [ "$(stat -c '%h' -- "$path")" = 1 ] \
              || fail_render "managed runtime destination link count is unsafe"
          fi
        }

        validate_existing_destination "$host_dir/bootstrap.environment" 400
        validate_existing_destination "$host_dir/environment" 400
        validate_existing_destination "$app_dir/seafile.env" 400
        validate_existing_destination "$app_dir/seahub_settings.py" 400
        validate_existing_destination "$app_dir/seafevents.conf" 400
        validate_existing_destination "$app_dir/seafile.conf" 444
        validate_existing_destination "$app_dir/seafdav.conf" 444
        validate_existing_destination "$metadata_dir/seafile.conf" 444

        normalized="$(mktemp "$host_dir/.validated.XXXXXX")"
        host_bootstrap="$(mktemp "$host_dir/.bootstrap.environment.XXXXXX")"
        host_environment="$(mktemp "$host_dir/.environment.XXXXXX")"
        app_environment="$(mktemp "$app_dir/.seafile.env.XXXXXX")"
        seahub_settings="$(mktemp "$app_dir/.seahub_settings.py.XXXXXX")"
        seafevents="$(mktemp "$app_dir/.seafevents.conf.XXXXXX")"
        seafile_conf="$(mktemp "$app_dir/.seafile.conf.XXXXXX")"
        seafdav_conf="$(mktemp "$app_dir/.seafdav.conf.XXXXXX")"
        metadata_conf=""
        metadata_open=0

        cleanup_render() {
          rm -f -- "$normalized" "$host_bootstrap" "$host_environment" \
            "$app_environment" "$seahub_settings" "$seafevents" \
            "$seafile_conf" "$seafdav_conf" "''${metadata_conf:-}"
          if [ "$metadata_open" -eq 1 ]; then
            chmod 0555 "$metadata_dir"
          fi
        }
        trap cleanup_render EXIT

        parse_command="''${SEAFILE_PARSE_ENVIRONMENT_COMMAND:-seafile-parse-environment}"
        "$parse_command" "$source_file" "$normalized"
        declare -A values=()
        while IFS= read -r line || [ -n "$line" ]; do
          key="''${line%%=*}"
          values["$key"]="''${line#*=}"
        done <"$normalized"

        bootstrap_keys=(
          ${lib.concatMapStringsSep "\n      " lib.escapeShellArg requiredEnvironmentKeys}
        )
        established_keys=(
          SEAFILE_MYSQL_DB_PASSWORD
          REDIS_PASSWORD
          JWT_PRIVATE_KEY
          SEAHUB_SECRET_KEY
          INIT_SEAFILE_ADMIN_EMAIL
          INIT_SEAFILE_ADMIN_PASSWORD
          SEAFILE_OAUTH_CLIENT_ID
          SEAFILE_OAUTH_CLIENT_SECRET
          ONLYOFFICE_JWT_SECRET
        )
        emit_key() {
          local destination="$1"
          local key="$2"
          printf '%s=%s\n' "$key" "''${values[$key]}" >>"$destination"
        }

        : >"$host_bootstrap"
        for key in "''${bootstrap_keys[@]}"; do emit_key "$host_bootstrap" "$key"; done
        : >"$host_environment"
        for key in "''${established_keys[@]}"; do emit_key "$host_environment" "$key"; done
        cp "$host_environment" "$app_environment"
        cat >>"$app_environment" <<'EOF'
    SEAFILE_SERVER_PROTOCOL=https
    SEAFILE_MYSQL_DB_HOST=database
    SEAFILE_REDIS_HOST=seafile-redis
    SEAFILE_REDIS_PORT=6379
    TIME_ZONE=Europe/Paris
    EOF
        printf '%s=%s\n' SEAFILE_SERVER_HOSTNAME ${lib.escapeShellArg (lib.removePrefix "https://" cfg.publicUrl)} >>"$app_environment"

        cat >"$seahub_settings" <<'EOF'
    ${seahubSettingsText}
    EOF

        basic_token="$(
          printf '%s:%s' "''${values[INIT_SS_ADMIN_USER]}" "''${values[INIT_SS_ADMIN_PASSWORD]}" \
            | base64 | tr -d '\n'
        )"
        cat >"$seafevents" <<EOF
    [SEASEARCH]
    enabled = true
    url = http://seafile-seasearch:4080
    interval = 600
    index_office_pdf = true
    authorization = Basic $basic_token

    [INDEX FILES]
    enabled = false
    EOF

        cat >"$seafile_conf" <<'EOF'
    [fileserver]
    host = 0.0.0.0
    port = 8082

    [database]
    host = database
    port = 3306
    type = mysql
    EOF
        cat >"$seafdav_conf" <<'EOF'
    [WEBDAV]
    enabled = false
    EOF

        chmod 0400 "$normalized" "$host_bootstrap" "$host_environment" \
          "$app_environment" "$seahub_settings" "$seafevents"
        chmod 0444 "$seafile_conf" "$seafdav_conf"

        [ "$(wc -l <"$host_bootstrap")" -eq 12 ] \
          || fail_render "bootstrap environment has an unexpected key count"
        [ "$(wc -l <"$host_environment")" -eq 9 ] \
          || fail_render "established environment has an unexpected key count"
        grep -F -x '[SEASEARCH]' "$seafevents" >/dev/null \
          || fail_render "SeaSearch configuration is incomplete"
        grep -F -x '[INDEX FILES]' "$seafevents" >/dev/null \
          || fail_render "legacy index configuration is incomplete"
        grep -F -x 'enabled = false' "$seafevents" >/dev/null \
          || fail_render "legacy index configuration is not disabled"
        grep -F -x '[fileserver]' "$seafile_conf" >/dev/null \
          || fail_render "Seafile configuration is incomplete"

        chmod 0700 "$metadata_dir"
        metadata_open=1
        metadata_conf="$(mktemp "$metadata_dir/.seafile.conf.XXXXXX")"
        cp "$seafile_conf" "$metadata_conf"
        chmod 0444 "$metadata_conf"

        mv -fT -- "$host_bootstrap" "$host_dir/bootstrap.environment"
        mv -fT -- "$host_environment" "$host_dir/environment"
        mv -fT -- "$app_environment" "$app_dir/seafile.env"
        mv -fT -- "$seahub_settings" "$app_dir/seahub_settings.py"
        mv -fT -- "$seafevents" "$app_dir/seafevents.conf"
        mv -fT -- "$seafile_conf" "$app_dir/seafile.conf"
        mv -fT -- "$seafdav_conf" "$app_dir/seafdav.conf"
        mv -fT -- "$metadata_conf" "$metadata_dir/seafile.conf"
        chmod 0555 "$metadata_dir"
        metadata_open=0

        rm -f -- "$normalized"
        trap - EXIT
  '';
  renderRuntimeConfig = pkgs.writeShellApplication {
    name = "seafile-render-runtime-config";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.docker
      pkgs.findutils
      pkgs.gnugrep
      pkgs.util-linux
      parseEnvironment
    ];
    text = renderRuntimeConfigScript;
  };
  reconcileRuntimeConfigScript = ''
    set -euo pipefail
    umask 077

    source_file=${lib.escapeShellArg secret.path}
    app_dir=/run/seafile-app
    state_dir=${lib.escapeShellArg cfg.stateDir}
    container_config_dir=/run/seafile
    lock_file=/run/lock/seafile-maintenance.lock
    lock_timeout=1800
    wait_timeout=1800

    usage() {
      echo "usage: seafile-reconcile-runtime-config [--source PATH --app-dir PATH --state-dir PATH --container-config-dir PATH --lock-file PATH --lock-timeout SECONDS --wait-timeout SECONDS]" >&2
      exit 64
    }
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --source) source_file="$2"; shift 2 ;;
        --app-dir) app_dir="$2"; shift 2 ;;
        --state-dir) state_dir="$2"; shift 2 ;;
        --container-config-dir) container_config_dir="$2"; shift 2 ;;
        --lock-file) lock_file="$2"; shift 2 ;;
        --lock-timeout) lock_timeout="$2"; shift 2 ;;
        --wait-timeout) wait_timeout="$2"; shift 2 ;;
        *) usage ;;
      esac
    done

    fail_reconcile() {
      echo "Seafile runtime configuration reconciliation failed: $1" >&2
      exit 65
    }

    install -d -m 0755 "$(dirname "$lock_file")"
    inherited_fd="''${SEAFILE_MAINTENANCE_LOCK_FD:-}"
    if [ -n "$inherited_fd" ]; then
      [[ "$inherited_fd" =~ ^[0-9]+$ ]] || fail_reconcile "inherited lock proof is malformed"
      [ "''${SEAFILE_ORCHESTRATION_STOPPED:-0}" = 1 ] \
        || fail_reconcile "inherited lock lacks stopped-orchestration proof"
      [ -e "/proc/$$/fd/$inherited_fd" ] \
        || fail_reconcile "inherited lock descriptor is unavailable"
      [ "$(readlink -f "/proc/$$/fd/$inherited_fd")" = "$(readlink -f "$lock_file")" ] \
        || fail_reconcile "inherited lock targets the wrong file"
    else
      exec 9>"$lock_file"
      flock -w "$lock_timeout" 9 || fail_reconcile "maintenance lock could not be acquired"
    fi

    docker_command="''${SEAFILE_DOCKER_COMMAND:-docker}"
    set +e
    live_containers="$($docker_command ps --quiet --filter label=com.docker.compose.project=seafile 2>/dev/null)"
    docker_status=$?
    set -e
    [ "$docker_status" -eq 0 ] || fail_reconcile "owned-container state could not be verified"
    [ -z "$live_containers" ] || fail_reconcile "owned containers are still running"

    expected_owner="''${SEAFILE_EXPECTED_OWNER:-0:0}"
    [ -d "$app_dir" ] && [ ! -L "$app_dir" ] || fail_reconcile "runtime application directory is unsafe"
    [ "$(stat -c '%u:%g' -- "$app_dir")" = "$expected_owner" ] \
      || fail_reconcile "runtime application directory owner is unsafe"

    deadline="$(( $(date +%s) + wait_timeout ))"
    config_dir="$state_dir/shared/seafile/conf"
    current_version="$state_dir/shared/seafile/seafile-data/current_version"
    while [ ! -s "$current_version" ] || [ ! -d "$config_dir" ] || [ -L "$config_dir" ]; do
      [ "$(date +%s)" -lt "$deadline" ] \
        || fail_reconcile "upstream bootstrap output did not become ready"
      sleep 1
    done
    [ "$(stat -c '%u:%g' -- "$config_dir")" = "$expected_owner" ] \
      || fail_reconcile "upstream configuration owner is unsafe"

    normalized="$(mktemp "$app_dir/.reconcile-environment.XXXXXX")"
    patterns="$(mktemp "$app_dir/.reconcile-patterns.XXXXXX")"
    cleanup_reconcile() {
      rm -f -- "$normalized" "$patterns"
    }
    trap cleanup_reconcile EXIT
    parse_command="''${SEAFILE_PARSE_ENVIRONMENT_COMMAND:-seafile-parse-environment}"
    "$parse_command" "$source_file" "$normalized"
    declare -A values=()
    while IFS= read -r line || [ -n "$line" ]; do
      key="''${line%%=*}"
      values["$key"]="''${line#*=}"
      printf '%s\n' "''${line#*=}" >>"$patterns"
    done <"$normalized"
    basic_token="$(
      printf '%s:%s' "''${values[INIT_SS_ADMIN_USER]}" "''${values[INIT_SS_ADMIN_PASSWORD]}" \
        | base64 | tr -d '\n'
    )"
    printf '%s\n' "$basic_token" >>"$patterns"
    chmod 0400 "$patterns"

    declare -A targets=(
      [.env]="$container_config_dir/seafile.env"
      [seahub_settings.py]="$container_config_dir/seahub_settings.py"
      [seafevents.conf]="$container_config_dir/seafevents.conf"
      [seafile.conf]="$container_config_dir/seafile.conf"
      [seafdav.conf]="$container_config_dir/seafdav.conf"
    )
    managed_names=(.env seahub_settings.py seafevents.conf seafile.conf seafdav.conf)

    while IFS= read -r -d "" linked; do
      allowed=0
      for name in "''${managed_names[@]}"; do
        [ "$linked" = "$config_dir/$name" ] && allowed=1
      done
      [ "$allowed" -eq 1 ] || fail_reconcile "persistent state contains an unexpected symlink"
    done < <(find "$state_dir/shared/seafile" -type l -print0)

    for name in "''${managed_names[@]}"; do
      path="$config_dir/$name"
      expected_target="''${targets[$name]}"
      [ "''${expected_target#/}" != "$expected_target" ] \
        || fail_reconcile "managed runtime target is not absolute"
      if [ -L "$path" ]; then
        [ "$(readlink "$path")" = "$expected_target" ] \
          || fail_reconcile "managed path targets an unexpected runtime file"
        [ "$(stat -c '%u:%g' -- "$path")" = "$expected_owner" ] \
          || fail_reconcile "managed symlink owner is unsafe"
      elif [ -e "$path" ]; then
        [ -f "$path" ] || fail_reconcile "managed path is not a regular file"
        [ "$(stat -c '%u:%g' -- "$path")" = "$expected_owner" ] \
          || fail_reconcile "managed path owner is unsafe"
        mode="$(stat -c '%a' -- "$path")"
        case "$mode" in
          400 | 440 | 444 | 600 | 640 | 644) ;;
          700) [ "$name" = seahub_settings.py ] || fail_reconcile "managed path mode is unsafe" ;;
          *) fail_reconcile "managed path mode is unsafe" ;;
        esac
      fi
    done

    for name in "''${managed_names[@]}"; do
      path="$config_dir/$name"
      expected_target="''${targets[$name]}"
      if [ -L "$path" ]; then
        continue
      fi
      temporary_link="$(mktemp "$config_dir/.$name.XXXXXX")"
      rm -f -- "$temporary_link"
      ln -s "$expected_target" "$temporary_link"
      mv -T -- "$temporary_link" "$config_dir/$name"
    done

    scan_file() {
      local candidate="$1"
      if grep -F -q -f "$patterns" -- "$candidate" 2>/dev/null; then
        fail_reconcile "persistent configuration contains sensitive runtime material"
      fi
    }
    while IFS= read -r -d "" candidate; do
      scan_file "$candidate"
    done < <(
      find "$state_dir/shared" \
        \( -path "$state_dir/shared/seafile/seafile-data/storage" \
          -o -path "$state_dir/shared/seafile/seafile-data/metadata" \
          -o -path "$state_dir/shared/logs" \
          -o -path "$state_dir/shared/seafile/logs" \) -prune \
        -o -type f -print0
    )
    for log_tree in "$state_dir/shared/logs" "$state_dir/shared/seafile/logs"; do
      if [ -e "$log_tree" ] || [ -L "$log_tree" ]; then
        [ -d "$log_tree" ] && [ ! -L "$log_tree" ] \
          || fail_reconcile "persistent log tree is unsafe"
        log_entry_count="$(find "$log_tree" -mindepth 1 -printf . | wc -c)"
        [ "$log_entry_count" -le 10000 ] \
          || fail_reconcile "persistent log tree exceeds its entry bound"
        unsafe_entry_count="$(find "$log_tree" -mindepth 1 ! -type d ! -type f -printf . | wc -c)"
        [ "$unsafe_entry_count" -eq 0 ] \
          || fail_reconcile "persistent log tree contains an unsafe entry"
        oversized_count="$(find "$log_tree" -type f -size +16777215c -printf . | wc -c)"
        [ "$oversized_count" -eq 0 ] \
          || fail_reconcile "persistent log tree contains an oversized file"
      fi
    done
    for log_tree in "$state_dir/shared/logs" "$state_dir/shared/seafile/logs"; do
      if [ -d "$log_tree" ]; then
        while IFS= read -r -d "" candidate; do
          scan_file "$candidate"
        done < <(find "$log_tree" -type f -print0)
      fi
    done

    rm -f -- "$normalized" "$patterns"
    trap - EXIT
  '';
  reconcileRuntimeConfig = pkgs.writeShellApplication {
    name = "seafile-reconcile-runtime-config";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.docker
      pkgs.findutils
      pkgs.gnugrep
      pkgs.util-linux
      parseEnvironment
    ];
    text = reconcileRuntimeConfigScript;
  };
  runtimeConfigContractText = ''
    Seafile runtime secrets are rendered under /run/seafile-host and /run/seafile-app.
    Metadata sees only /run/seafile-metadata/seafile.conf through a directory bind.
    seafile-config.service uses RuntimeDirectoryPreserve=yes and renders only while
    /run/lock/seafile-maintenance.lock is held and no owned container is live.
  '';
in
{
  options.shulker.system.modules.seafile = {
    requiredEnvironmentKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      readOnly = true;
      description = "Exact structured keys required by the Seafile OpNix environment.";
    };
    parseEnvironmentScript = lib.mkOption {
      type = lib.types.lines;
      readOnly = true;
      internal = true;
      description = "Strict non-evaluating Seafile environment parser source.";
    };
    parseEnvironmentPackage = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      internal = true;
      description = "Packaged strict Seafile environment parser.";
    };
    parseEnvironmentRuntimeInputs = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      readOnly = true;
      internal = true;
      description = "Runtime closure for the packaged Seafile environment parser.";
    };
    renderRuntimeConfigScript = lib.mkOption {
      type = lib.types.lines;
      readOnly = true;
      internal = true;
      description = "Atomic Seafile runtime configuration renderer source.";
    };
    renderRuntimeConfigPackage = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      internal = true;
      description = "Packaged Seafile runtime configuration renderer.";
    };
    reconcileRuntimeConfigScript = lib.mkOption {
      type = lib.types.lines;
      readOnly = true;
      internal = true;
      description = "Fail-closed Seafile persistent configuration reconciler source.";
    };
    reconcileRuntimeConfigPackage = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      internal = true;
      description = "Packaged Seafile persistent configuration reconciler.";
    };
    runtimeConfigContractText = lib.mkOption {
      type = lib.types.lines;
      readOnly = true;
      internal = true;
      description = "Non-secret runtime configuration contract for evaluation checks.";
    };
    seahubSettingsText = lib.mkOption {
      type = lib.types.lines;
      readOnly = true;
      internal = true;
      description = "Rendered non-secret Seahub policy source for evaluation contracts.";
    };
  };

  config = lib.mkIf cfg.enable {
    shulker.system.secretPreflight.schemas.seafileEnv = {
      format = "dotenv";
      inherit exactKeys;
    };

    shulker.system.modules.seafile = {
      inherit
        parseEnvironmentRuntimeInputs
        parseEnvironmentScript
        reconcileRuntimeConfigScript
        renderRuntimeConfigScript
        requiredEnvironmentKeys
        runtimeConfigContractText
        seahubSettingsText
        ;
      parseEnvironmentPackage = parseEnvironment;
      renderRuntimeConfigPackage = renderRuntimeConfig;
      reconcileRuntimeConfigPackage = reconcileRuntimeConfig;
    };

    environment.systemPackages = [
      parseEnvironment
      renderRuntimeConfig
      reconcileRuntimeConfig
    ];

    systemd.services.seafile-config = {
      description = "Render protected Seafile runtime configuration";
      requires = [
        "opnix-secrets.service"
        "seafile-state.service"
      ];
      after = [
        "opnix-secrets.service"
        "seafile-state.service"
      ];
      before = [
        "borgmatic.service"
        "seafile-image-pull.service"
        "seafile-compose.service"
        "seafile-backup-prepare.service"
        "seafile-maintenance.service"
      ];
      unitConfig.ConditionFileNotEmpty = secret.path;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        RuntimeDirectory = [
          "seafile-host"
          "seafile-app"
          "seafile-metadata"
        ];
        RuntimeDirectoryMode = "0700";
        RuntimeDirectoryPreserve = "yes";
        UMask = "0077";
        ExecStart = "${renderRuntimeConfig}/bin/seafile-render-runtime-config";
      };
    };
  };
}
