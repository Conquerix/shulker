{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.shulker.system.modules.seafile;
  secret = config.services.onepassword-secrets.secrets.seafileEnv;
  secretConsumers = [
    "seafile-config"
    "seafile-image-pull"
    "seafile-compose"
  ];
  releaseVersions = {
    seafile = "13.0.25";
    mariadb = "10.11.18";
    redis = "7.4.10-alpine";
    seasearch = "1.0.4";
    notification = "13.0.21";
    metadata = "13.0.22";
    onlyoffice = "9.4.0.1";
  };
  imageIsPinnedTo =
    version: image:
    let
      digestParts = lib.splitString "@sha256:" image;
      digest = if builtins.length digestParts == 2 then builtins.elemAt digestParts 1 else "";
    in
    lib.hasInfix ":${version}@sha256:" image
    && builtins.stringLength digest == 64
    && builtins.match "[0-9a-f]+" digest != null;
  validateStateScript = ''
    set -euo pipefail

    state_dir=${lib.escapeShellArg cfg.stateDir}
    dataset=${lib.escapeShellArg cfg.dataset}
    expected_quota=${lib.escapeShellArg (toString cfg.datasetQuotaBytes)}
    initialize=0

    usage() {
      echo "usage: seafile-validate-state [--initialize] [--state-dir PATH --dataset DATASET --quota BYTES]" >&2
      exit 64
    }

    while [ "$#" -gt 0 ]; do
      case "$1" in
        --initialize)
          initialize=1
          shift
          ;;
        --state-dir)
          [ "$#" -ge 2 ] || usage
          state_dir="$2"
          shift 2
          ;;
        --dataset)
          [ "$#" -ge 2 ] || usage
          dataset="$2"
          shift 2
          ;;
        --quota)
          [ "$#" -ge 2 ] || usage
          expected_quota="$2"
          shift 2
          ;;
        *)
          usage
          ;;
      esac
    done

    fail_state() {
      echo "Seafile state validation failed: $1" >&2
      exit 65
    }

    actual_source="$(findmnt --noheadings --output SOURCE --target "$state_dir")"
    [ "$actual_source" = "$dataset" ] \
      || fail_state "mount source does not match the evaluated dataset"

    actual_type="$(findmnt --noheadings --output FSTYPE --target "$state_dir")"
    [ "$actual_type" = zfs ] \
      || fail_state "state path is not a ZFS mount"

    actual_target="$(findmnt --noheadings --output TARGET --target "$state_dir")"
    [ "$actual_target" = "$state_dir" ] \
      || fail_state "stateDir is not the exact ZFS mount target"

    actual_quota="$(zfs get -Hp -o value quota "$dataset")"
    [ "$actual_quota" = "$expected_quota" ] \
      || fail_state "numeric ZFS quota does not match the evaluated configuration"

    validate_property() {
      local property="$1"
      local expected="$2"
      local actual
      actual="$(zfs get -H -o value "$property" "$dataset")"
      [ "$actual" = "$expected" ] \
        || fail_state "ZFS property $property does not match the evaluated configuration"
    }

    validate_property compression zstd
    validate_property atime off
    validate_property acltype posix
    validate_property xattr sa
    validate_property dnodesize auto

    [ "$(stat --format %F -- "$state_dir")" = directory ] \
      || fail_state "mount target is not a directory"

    marker="$state_dir/.seafile-state-transaction"
    staging="$state_dir/.seafile-state-staging"
    marker_version="seafile-state-transaction-v1"
    initialized_paths=(shared database search onlyoffice backups control)

    path_present() {
      [ -e "$1" ] || [ -L "$1" ]
    }

    validate_fresh_directory() {
      local path="$1"
      local expected_mode="$2"
      local label="$3"

      [ "$(stat --format %F -- "$path")" = directory ] \
        || fail_state "$label is missing, symlinked, or not a directory"
      [ "$(stat --format %u:%g -- "$path")" = 0:0 ] \
        || fail_state "$label is not owned by root"
      [ "$(stat --format %a -- "$path")" = "$expected_mode" ] \
        || fail_state "$label has an unsafe or unexpected mode"
    }

    validate_empty_directory() {
      local path="$1"
      local label="$2"
      [ -z "$(find "$path" -mindepth 1 -maxdepth 1 -print -quit)" ] \
        || fail_state "$label is not empty during state initialization"
    }

    validate_fresh_tree() {
      local path="$1"
      local relative_path="$2"
      local child_count child child_name

      case "$relative_path" in
        database | backups | control)
          validate_fresh_directory "$path" 700 "$relative_path"
          validate_empty_directory "$path" "$relative_path"
          ;;
        onlyoffice)
          validate_fresh_directory "$path" 750 onlyoffice
          child_count=0
          while IFS= read -r -d "" child; do
            child_name="''${child##*/}"
            case "$child_name" in
              logs | data | lib) ;;
              *) fail_state "onlyoffice contains an unexpected initialization path" ;;
            esac
            child_count="$((child_count + 1))"
          done < <(find "$path" -mindepth 1 -maxdepth 1 -print0)
          [ "$child_count" -eq 3 ] \
            || fail_state "onlyoffice does not contain exactly its three bind sources"
          for child_name in logs data lib; do
            validate_fresh_directory "$path/$child_name" 750 "onlyoffice/$child_name"
            validate_empty_directory "$path/$child_name" "onlyoffice/$child_name"
          done
          ;;
        shared | search)
          validate_fresh_directory "$path" 750 "$relative_path"
          validate_empty_directory "$path" "$relative_path"
          ;;
        *)
          fail_state "transaction contains an unknown state path"
          ;;
      esac
    }

    validate_transaction_marker() {
      [ "$(stat --format %F -- "$marker")" = "regular file" ] \
        || fail_state "state transaction marker is missing, symlinked, or not a regular file"
      [ "$(stat --format %u:%g -- "$marker")" = 0:0 ] \
        || fail_state "state transaction marker is not owned by root"
      [ "$(stat --format %a -- "$marker")" = 600 ] \
        || fail_state "state transaction marker is not mode 0600"
      printf '%s\n' "$marker_version" | cmp --silent - "$marker" \
        || fail_state "state transaction marker has unexpected content"
    }

    validate_transaction_entries() {
      local entry entry_name relative_path published staged
      local published_present staged_present
      validate_transaction_marker

      if path_present "$staging"; then
        validate_fresh_directory "$staging" 700 "state transaction staging"
      fi

      while IFS= read -r -d "" entry; do
        entry_name="''${entry##*/}"
        case "$entry_name" in
          .seafile-state-transaction | .seafile-state-staging | shared | database | search | onlyoffice | backups | control) ;;
          *) fail_state "state transaction has an unexpected top-level path" ;;
        esac
      done < <(find "$state_dir" -mindepth 1 -maxdepth 1 -print0)

      if path_present "$staging"; then
        while IFS= read -r -d "" entry; do
          entry_name="''${entry##*/}"
          case "$entry_name" in
            shared | database | search | onlyoffice | backups | control) ;;
            *) fail_state "state transaction staging has an unexpected path" ;;
          esac
        done < <(find "$staging" -mindepth 1 -maxdepth 1 -print0)
      fi

      for relative_path in "''${initialized_paths[@]}"; do
        published="$state_dir/$relative_path"
        staged="$staging/$relative_path"
        published_present=0
        staged_present=0
        path_present "$published" && published_present=1
        if path_present "$staging" && path_present "$staged"; then
          staged_present=1
        fi
        [ "$((published_present + staged_present))" -eq 1 ] \
          || fail_state "$relative_path is missing or duplicated across the state transaction"
        if [ "$published_present" -eq 1 ]; then
          validate_fresh_tree "$published" "$relative_path"
        else
          validate_fresh_tree "$staged" "$relative_path"
        fi
      done
    }

    first_entry="$(find "$state_dir" -mindepth 1 -maxdepth 1 -print -quit)"
    transaction_active=0
    if path_present "$marker"; then
      [ "$initialize" -eq 1 ] \
        || fail_state "an interrupted state transaction requires initialization mode"
      transaction_active=1
    elif [ -z "$first_entry" ]; then
      [ "$initialize" -eq 1 ] \
        || fail_state "empty state is accepted only for first initialization"

      install -m 0600 -o 0 -g 0 /dev/null "$marker"
      printf '%s\n' "$marker_version" >"$marker"
      sync -f "$marker"
      sync -f "$state_dir"

      install -d -m 0700 -o 0 -g 0 "$staging"
      install -d -m 0750 -o 0 -g 0 \
        "$staging/shared" \
        "$staging/search" \
        "$staging/onlyoffice" \
        "$staging/onlyoffice/logs" \
        "$staging/onlyoffice/data" \
        "$staging/onlyoffice/lib"
      install -d -m 0700 -o 0 -g 0 \
        "$staging/database" \
        "$staging/backups" \
        "$staging/control"
      sync -f "$state_dir"
      transaction_active=1
    elif path_present "$staging"; then
      fail_state "unmarked state transaction staging is not recoverable"
    fi

    if [ "$transaction_active" -eq 1 ]; then
      validate_transaction_entries
      for relative_path in "''${initialized_paths[@]}"; do
        if path_present "$staging/$relative_path"; then
          mv -- "$staging/$relative_path" "$state_dir/$relative_path"
        fi
      done
      validate_transaction_entries
      if path_present "$staging"; then
        rmdir -- "$staging"
      fi
      sync -f "$state_dir"
      unlink "$marker"
      sync -f "$state_dir"
    fi

    validate_path() {
      local relative_path="$1"
      local expected_mode="$2"
      local allowed_managed_owner="''${3:-}"
      local path="$state_dir/$relative_path"
      local actual_owner actual_mode

      [ "$(stat --format %F -- "$path")" = directory ] \
        || fail_state "$relative_path is missing, symlinked, or not a directory"

      actual_owner="$(stat --format %u:%g -- "$path")"
      if [ "$actual_owner" != 0:0 ] \
        && { [ -z "$allowed_managed_owner" ] || [ "$actual_owner" != "$allowed_managed_owner" ]; }
      then
        fail_state "$relative_path has an unexpected owner or group"
      fi

      actual_mode="$(stat --format %a -- "$path")"
      [ "$actual_mode" = "$expected_mode" ] \
        || fail_state "$relative_path has an unsafe or unexpected mode"
    }

    validate_path shared 750
    validate_path database 700 999:999
    validate_path search 750
    validate_path onlyoffice 750
    validate_path onlyoffice/logs 750
    validate_path onlyoffice/data 750
    validate_path onlyoffice/lib 750
    validate_path backups 700
    validate_path control 700

  '';
  validateState = pkgs.writeShellApplication {
    name = "seafile-validate-state";
    runtimeInputs = [
      config.boot.zfs.package
      pkgs.coreutils
      pkgs.findutils
      pkgs.util-linux
    ];
    text = validateStateScript;
  };
in
{
  options.shulker.system.modules.seafile = {
    enable = lib.mkEnableOption "Seafile Pro file collaboration";

    version = lib.mkOption {
      type = lib.types.str;
      default = releaseVersions.seafile;
      readOnly = true;
      description = "Configured Seafile Pro release.";
    };

    licenseUserLimit = lib.mkOption {
      type = lib.types.ints.positive;
      default = 3;
      readOnly = true;
      description = "Maximum users allowed by the pilot license.";
    };

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/seafile";
      description = "Mount point containing all persistent Seafile state.";
    };

    dataset = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Dedicated legacy-mounted ZFS dataset for Seafile.";
    };

    datasetQuotaBytes = lib.mkOption {
      type = lib.types.ints.positive;
      default = 1649267441664;
      description = "Expected ZFS dataset quota in bytes.";
    };

    bindAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Loopback address used for all host publications.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 23239;
      description = "Loopback Seafile HTTP port intended for Pangolin.";
    };

    onlyOfficePort = lib.mkOption {
      type = lib.types.port;
      default = 23240;
      description = "Loopback OnlyOffice HTTP port intended for Pangolin.";
    };

    notificationPort = lib.mkOption {
      type = lib.types.port;
      default = 23241;
      description = "Loopback Notification WebSocket port intended for Pangolin.";
    };

    publicUrl = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Public HTTPS URL used by Seafile clients.";
    };

    onlyOfficePublicUrl = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Public HTTPS URL used by OnlyOffice.";
    };

    oidcIssuer = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "External OpenID Connect issuer used by Seafile.";
    };

    metadataFileCountLimit = lib.mkOption {
      type = lib.types.ints.positive;
      default = 100000;
      description = "Maximum file count processed by Metadata Server.";
    };

    metadataCacheSize = lib.mkOption {
      type = lib.types.str;
      default = "1GB";
      description = "Metadata Server object-cache size.";
    };

    metadataCheckUpdateInterval = lib.mkOption {
      type = lib.types.str;
      default = "30m";
      description = "Metadata Server reconciliation interval.";
    };

    editableExtensions = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "docx"
        "xlsx"
        "pptx"
        "csv"
      ];
      description = "File extensions editable through OnlyOffice.";
    };

    shareLinkForceUsePassword = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Require passwords on public share links.";
    };

    shareLinkPasswordMinLength = lib.mkOption {
      type = lib.types.ints.positive;
      default = 12;
      description = "Minimum share-link password length.";
    };

    shareLinkPasswordStrengthLevel = lib.mkOption {
      type = lib.types.int;
      default = 3;
      description = "Required Seafile share-link password strength level.";
    };

    shareLinkExpireDaysDefault = lib.mkOption {
      type = lib.types.ints.positive;
      default = 7;
      description = "Default public share-link expiry in days.";
    };

    shareLinkExpireDaysMax = lib.mkOption {
      type = lib.types.ints.positive;
      default = 30;
      description = "Maximum public share-link expiry in days.";
    };

    uploadLinkExpireDaysDefault = lib.mkOption {
      type = lib.types.ints.positive;
      default = 7;
      description = "Default upload-link expiry in days.";
    };

    uploadLinkExpireDaysMax = lib.mkOption {
      type = lib.types.ints.positive;
      default = 30;
      description = "Maximum upload-link expiry in days.";
    };

    shareLinkLoginRequired = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Require a Seafile login in addition to link credentials.";
    };

    logicalDumpRetention = lib.mkOption {
      type = lib.types.ints.positive;
      default = 14;
      description = "Number of validated logical MariaDB dumps to retain.";
    };

    backUpData = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Include a consistent Seafile ZFS snapshot in Borgmatic.";
    };

    backupSnapshotName = lib.mkOption {
      type = lib.types.str;
      default = "borgmatic";
      description = "Exact ZFS snapshot name reserved for Borgmatic backups.";
    };

    seafileImage = lib.mkOption {
      type = lib.types.str;
      default = "docker.io/seafileltd/seafile-pro-mc:13.0.25@sha256:82fa05a844303912066a7ded86864dbf6fb45273f08f6448a0842863beefabb4";
      description = "Digest-pinned Seafile Pro image.";
    };

    databaseImage = lib.mkOption {
      type = lib.types.str;
      default = "docker.io/library/mariadb:10.11.18@sha256:992d5668eb9a5f153253c2f13d4e72717b7c24a27f271f47647af3b7e5a3c109";
      description = "Digest-pinned MariaDB image.";
    };

    redisImage = lib.mkOption {
      type = lib.types.str;
      default = "docker.io/library/redis:7.4.10-alpine@sha256:9702d01c1f10c3ea9f48211b4362e44f154ff02d063e6f7268eba804059f53bf";
      description = "Digest-pinned Redis image.";
    };

    seasearchImage = lib.mkOption {
      type = lib.types.str;
      default = "docker.io/seafileltd/seasearch:1.0.4@sha256:192284f4f2fe7ca879fdfb8301dd0ebc6a5da6efaa4a99c53febfad8a75b7edc";
      description = "Digest-pinned SeaSearch image.";
    };

    notificationImage = lib.mkOption {
      type = lib.types.str;
      default = "docker.io/seafileltd/notification-server:13.0.21@sha256:be7b6c6887b921a86ec4990c0c8b0b57f7f5ba3046dcf0adb007bbc80abaec86";
      description = "Digest-pinned Notification Server image.";
    };

    metadataImage = lib.mkOption {
      type = lib.types.str;
      default = "docker.io/seafileltd/seafile-md-server:13.0.22@sha256:8ccee7ea9139c288a24bf1d7e29c5a1579256ee5f887eb93967e790f571eb973";
      description = "Digest-pinned Metadata Server image.";
    };

    onlyOfficeImage = lib.mkOption {
      type = lib.types.str;
      default = "docker.io/onlyoffice/documentserver:9.4.0.1@sha256:e231bc62da8c1f0c1f78188f8c7e17e67716f38955d0ad1d703cf911ad6db84b";
      description = "Digest-pinned OnlyOffice Document Server image.";
    };

    oauthCallbackUrl = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      description = "Derived Seafile OAuth callback URL.";
    };

    notificationPublicUrl = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      description = "Derived public Notification URL.";
    };

    notificationInternalUrl = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      description = "Derived private Notification service URL.";
    };

    onlyOfficeApiUrl = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      description = "Derived OnlyOffice JavaScript API URL.";
    };

    releaseVersions = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      readOnly = true;
      description = "Reviewed release tags for the coupled Seafile stack.";
    };

    validateStateScript = lib.mkOption {
      type = lib.types.lines;
      readOnly = true;
      internal = true;
      description = "Fail-closed state validator source used by executable contracts.";
    };

    validateStatePackage = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      internal = true;
      description = "Packaged Seafile state validator.";
    };
  };

  config = lib.mkIf cfg.enable {
    shulker.system.modules.seafile = {
      oauthCallbackUrl = "${cfg.publicUrl}/oauth/callback/";
      notificationPublicUrl = "${cfg.publicUrl}/notification";
      notificationInternalUrl = "http://seafile-notification:8083";
      onlyOfficeApiUrl = "${cfg.onlyOfficePublicUrl}/web-apps/apps/api/documents/api.js";
      inherit releaseVersions validateStateScript;
      validateStatePackage = validateState;
    };

    assertions = [
      {
        assertion = lib.hasPrefix "https://" cfg.publicUrl;
        message = "Seafile publicUrl must use HTTPS.";
      }
      {
        assertion = lib.hasPrefix "https://" cfg.onlyOfficePublicUrl;
        message = "Seafile onlyOfficePublicUrl must use HTTPS.";
      }
      {
        assertion = lib.hasPrefix "https://" cfg.oidcIssuer;
        message = "Seafile oidcIssuer must use HTTPS.";
      }
      {
        assertion = lib.elem cfg.bindAddress [
          "127.0.0.1"
          "[::1]"
        ];
        message = "Seafile services must remain bound to host loopback.";
      }
      {
        assertion =
          builtins.length (
            lib.unique [
              cfg.port
              cfg.onlyOfficePort
              cfg.notificationPort
            ]
          ) == 3;
        message = "Seafile, OnlyOffice, and Notification must use distinct ports.";
      }
      {
        assertion = cfg.stateDir != "/" && lib.hasPrefix "/" cfg.stateDir;
        message = "Seafile stateDir must be a non-root absolute path.";
      }
      {
        assertion = cfg.dataset != "" && !(lib.hasInfix "@" cfg.dataset);
        message = "Seafile requires an exact non-snapshot ZFS dataset.";
      }
      {
        assertion = config.fileSystems.${cfg.stateDir}.fsType == "zfs";
        message = "Seafile stateDir must be declared as a ZFS filesystem.";
      }
      {
        assertion = !(lib.elem "zfsutil" config.fileSystems.${cfg.stateDir}.options);
        message = "Seafile uses a legacy-mounted ZFS dataset and must not enable zfsutil.";
      }
      {
        assertion = !cfg.backUpData || config.shulker.system.modules.backup.enable;
        message = "Seafile backup coverage requires the Borgmatic backup module.";
      }
      {
        assertion =
          cfg.backupSnapshotName == "borgmatic"
          && !(lib.hasInfix "/" cfg.backupSnapshotName)
          && !(lib.hasInfix "@" cfg.backupSnapshotName);
        message = "Seafile reserves only the borgmatic ZFS snapshot name.";
      }
      {
        assertion = imageIsPinnedTo releaseVersions.seafile cfg.seafileImage;
        message = "Seafile image must match the reviewed tag and digest format.";
      }
      {
        assertion = imageIsPinnedTo releaseVersions.mariadb cfg.databaseImage;
        message = "MariaDB image must match the reviewed tag and digest format.";
      }
      {
        assertion = imageIsPinnedTo releaseVersions.redis cfg.redisImage;
        message = "Redis image must match the reviewed tag and digest format.";
      }
      {
        assertion = imageIsPinnedTo releaseVersions.seasearch cfg.seasearchImage;
        message = "SeaSearch image must match the reviewed tag and digest format.";
      }
      {
        assertion = imageIsPinnedTo releaseVersions.notification cfg.notificationImage;
        message = "Notification image must match the reviewed tag and digest format.";
      }
      {
        assertion = imageIsPinnedTo releaseVersions.metadata cfg.metadataImage;
        message = "Metadata image must match the reviewed tag and digest format.";
      }
      {
        assertion = imageIsPinnedTo releaseVersions.onlyoffice cfg.onlyOfficeImage;
        message = "OnlyOffice image must match the reviewed tag and digest format.";
      }
      {
        assertion = cfg.metadataCacheSize != "" && cfg.metadataCheckUpdateInterval != "";
        message = "Seafile Metadata limits must be nonempty.";
      }
      {
        assertion =
          cfg.shareLinkForceUsePassword
          && cfg.shareLinkPasswordMinLength >= 12
          && cfg.shareLinkPasswordStrengthLevel >= 0
          && cfg.shareLinkPasswordStrengthLevel <= 4;
        message = "Seafile share links require the reviewed password policy range.";
      }
      {
        assertion =
          cfg.shareLinkExpireDaysDefault <= cfg.shareLinkExpireDaysMax
          && cfg.uploadLinkExpireDaysDefault <= cfg.uploadLinkExpireDaysMax;
        message = "Seafile link expiry defaults must not exceed their maxima.";
      }
      {
        assertion = secret.reference == "op://Shulker/${config.networking.hostName}/Seafile/Environment";
        message = "Seafile must use the host-scoped OpNix Environment field.";
      }
      {
        assertion =
          secret.services == secretConsumers
          && secret.owner == "root"
          && secret.group == "root"
          && secret.mode == "0400";
        message = "Seafile secret consumers and root-only permissions must remain ordered and exact.";
      }
    ];

    shulker.system.modules.containers.enable = true;

    environment.systemPackages = [ validateState ];

    fileSystems.${cfg.stateDir} = {
      device = cfg.dataset;
      fsType = "zfs";
      options = [ "nofail" ];
    };

    systemd.services.seafile-state = {
      description = "Validate and initialize persistent Seafile state";
      unitConfig.RequiresMountsFor = cfg.stateDir;
      script = ''
        ${validateState}/bin/seafile-validate-state --initialize
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
    };

    services.onepassword-secrets.secrets.seafileEnv = {
      reference = "op://Shulker/${config.networking.hostName}/Seafile/Environment";
      services = secretConsumers;
      owner = "root";
      group = "root";
      mode = "0400";
    };
  };
}
