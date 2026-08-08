{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.shulker.system.modules.paperless;
  validateState = pkgs.writeShellApplication {
    name = "paperless-validate-state";
    runtimeInputs = [
      config.boot.zfs.package
      pkgs.coreutils
      pkgs.util-linux
    ];
    text = ''
      readonly state_dir=${lib.escapeShellArg cfg.stateDir}
      readonly dataset=${lib.escapeShellArg cfg.dataset}
      readonly expected_quota=${lib.escapeShellArg (toString cfg.datasetQuotaBytes)}

      actual_source="$(findmnt --noheadings --output SOURCE --target "$state_dir")"
      if [ "$actual_source" != "$dataset" ]; then
        echo "Paperless state is not mounted from the expected ZFS dataset" >&2
        exit 65
      fi

      actual_quota="$(zfs get -Hp -o value quota "$dataset")"
      if [ "$actual_quota" != "$expected_quota" ]; then
        echo "Paperless ZFS quota does not match the evaluated configuration" >&2
        exit 65
      fi

      validate_property() {
        property="$1"
        expected="$2"
        actual="$(zfs get -H -o value "$property" "$dataset")"
        if [ "$actual" != "$expected" ]; then
          echo "Paperless ZFS property $property does not match the evaluated configuration" >&2
          exit 65
        fi
      }

      validate_property compression zstd
      validate_property atime off
      validate_property acltype posixacl
      validate_property xattr sa
      validate_property dnodesize auto
    '';
  };
in
{
  options.shulker.system.modules.paperless = {
    enable = lib.mkEnableOption "Paperless-ngx document archive";

    version = lib.mkOption {
      type = lib.types.str;
      default = "3.0.5";
      readOnly = true;
      description = "Configured Paperless-ngx release.";
    };

    uid = lib.mkOption {
      type = lib.types.int;
      default = 10002;
      description = "Host UID used for Paperless-managed files.";
    };

    gid = lib.mkOption {
      type = lib.types.int;
      default = 10002;
      description = "Host GID used for Paperless-managed files.";
    };

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/paperless";
      description = "Mount point containing all persistent Paperless state.";
    };

    dataset = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Dedicated ZFS dataset mounted at stateDir.";
    };

    datasetQuotaBytes = lib.mkOption {
      type = lib.types.ints.positive;
      default = 536870912000;
      description = "Expected ZFS dataset quota in bytes.";
    };

    bindAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Host address on which to publish Paperless HTTP.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 23238;
      description = "Loopback HTTP port intended for Pangolin.";
    };

    publicUrl = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Public HTTPS URL used by Paperless web and API clients.";
    };

    oidcIssuer = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "External OpenID Connect issuer used for Paperless authentication.";
    };

    ocrLanguage = lib.mkOption {
      type = lib.types.str;
      default = "fra+eng+deu";
      description = "Tesseract languages used for document OCR.";
    };

    searchLanguage = lib.mkOption {
      type = lib.types.str;
      default = "fr";
      description = "Tantivy stemming language used for full-text search.";
    };

    trashDelayDays = lib.mkOption {
      type = lib.types.ints.positive;
      default = 90;
      description = "Days deleted documents remain recoverable in Paperless trash.";
    };

    backUpData = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Include a consistent ZFS snapshot of Paperless in Borgmatic.";
    };

    backupSnapshotName = lib.mkOption {
      type = lib.types.str;
      default = "borgmatic";
      description = "Exact ZFS snapshot name reserved for Borgmatic backups.";
    };

    paperlessImage = lib.mkOption {
      type = lib.types.str;
      default = "ghcr.io/paperless-ngx/paperless-ngx:3.0.5@sha256:65a4cabf0169ea7fbd90ab7bb28ba3f8b5909613635acda1a03ad606f34b456b";
      description = "Digest-pinned Paperless-ngx image.";
    };

    valkeyImage = lib.mkOption {
      type = lib.types.str;
      default = "docker.io/valkey/valkey:9-alpine@sha256:ee91f7a174ac4d6a6b0685b3a60e321f0a9dbbb691f9b0e285be2ba1d1be8328";
      description = "Digest-pinned Valkey image.";
    };

    databaseImage = lib.mkOption {
      type = lib.types.str;
      default = "docker.io/library/postgres:18@sha256:a02db8cac496f15b094798a38254f14d6e00741f709360e5e00bb6668ea31636";
      description = "Digest-pinned PostgreSQL image.";
    };

    gotenbergImage = lib.mkOption {
      type = lib.types.str;
      default = "docker.io/gotenberg/gotenberg:8.34@sha256:67097317623a503ba2a6a7e9ae8db6929a1f7e1bbd88077bacf2d325fbdab923";
      description = "Digest-pinned Gotenberg image.";
    };

    tikaImage = lib.mkOption {
      type = lib.types.str;
      default = "docker.io/apache/tika:3.2.3.0-full@sha256:21d8052de04e491ccf66e8680ade4da6f3d453a56d59f740b4167e54167219b7";
      description = "Digest-pinned Apache Tika image.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.hasPrefix "https://" cfg.publicUrl;
        message = "Paperless publicUrl must use HTTPS.";
      }
      {
        assertion = lib.hasPrefix "https://" cfg.oidcIssuer;
        message = "Paperless oidcIssuer must use HTTPS.";
      }
      {
        assertion = lib.elem cfg.bindAddress [
          "127.0.0.1"
          "[::1]"
        ];
        message = "Paperless must remain bound to host loopback and be exposed through Pangolin.";
      }
      {
        assertion = lib.hasPrefix "/" cfg.stateDir;
        message = "Paperless stateDir must be an absolute path.";
      }
      {
        assertion = cfg.dataset != "";
        message = "Paperless requires a dedicated ZFS dataset.";
      }
      {
        assertion = !(lib.elem "zfsutil" config.fileSystems.${cfg.stateDir}.options);
        message = "Paperless uses a legacy-mounted ZFS dataset and must not enable zfsutil.";
      }
      {
        assertion = !cfg.backUpData || config.shulker.system.modules.backup.enable;
        message = "Paperless backup coverage requires the Borgmatic backup module.";
      }
      {
        assertion =
          cfg.backupSnapshotName == "borgmatic"
          && !(lib.hasInfix "/" cfg.backupSnapshotName)
          && !(lib.hasInfix "@" cfg.backupSnapshotName);
        message = "Paperless reserves only the borgmatic ZFS snapshot name.";
      }
      {
        assertion = lib.all (image: lib.hasInfix "@sha256:" image) [
          cfg.paperlessImage
          cfg.valkeyImage
          cfg.databaseImage
          cfg.gotenbergImage
          cfg.tikaImage
        ];
        message = "Every Paperless Compose image must be pinned by digest.";
      }
    ];

    shulker.system.modules.containers.enable = true;

    users.groups.paperless.gid = cfg.gid;
    users.users.paperless = {
      uid = cfg.uid;
      group = "paperless";
      isSystemUser = true;
      home = cfg.stateDir;
      createHome = false;
    };

    environment.systemPackages = [ validateState ];

    fileSystems.${cfg.stateDir} = {
      device = cfg.dataset;
      fsType = "zfs";
      options = [ "nofail" ];
    };

    systemd.services.paperless-state = {
      description = "Validate and prepare persistent Paperless state";
      unitConfig.RequiresMountsFor = cfg.stateDir;
      path = [ pkgs.coreutils ];
      script = ''
        ${validateState}/bin/paperless-validate-state

        install -d -m 0750 -o ${toString cfg.uid} -g ${toString cfg.gid} \
          ${lib.escapeShellArg cfg.stateDir}/data \
          ${lib.escapeShellArg cfg.stateDir}/media \
          ${lib.escapeShellArg cfg.stateDir}/consume \
          ${lib.escapeShellArg cfg.stateDir}/consume/family \
          ${lib.escapeShellArg cfg.stateDir}/consume/private \
          ${lib.escapeShellArg cfg.stateDir}/export \
          ${lib.escapeShellArg cfg.stateDir}/dumps
        install -d -m 0700 -o 999 -g 999 \
          ${lib.escapeShellArg cfg.stateDir}/postgres \
          ${lib.escapeShellArg cfg.stateDir}/redis
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
    };

    services.onepassword-secrets.secrets.paperlessEnv = {
      reference = "op://Shulker/${config.networking.hostName}/Paperless/Environment";
      services = [
        "paperless-image-pull"
        "paperless-compose"
      ];
      owner = "root";
      group = "root";
      mode = "0400";
    };
  };
}
