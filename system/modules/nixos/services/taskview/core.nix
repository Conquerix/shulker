# Refuse unmounted state before starting TaskView or preparing backups.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.shulker.system.modules.taskview;
  validateStateScript = ''
    readonly state_dir=${lib.escapeShellArg cfg.stateDir}
    readonly dataset=${lib.escapeShellArg cfg.dataset}
    readonly expected_quota=${lib.escapeShellArg (toString cfg.datasetQuotaBytes)}

    actual_source="$(findmnt --noheadings --output SOURCE --target "$state_dir")"
    if [ "$actual_source" != "$dataset" ]; then
      echo "TaskView state is not mounted from the expected ZFS dataset" >&2
      exit 65
    fi

    actual_quota="$(zfs get -Hp -o value quota "$dataset")"
    if [ "$actual_quota" != "$expected_quota" ]; then
      echo "TaskView ZFS quota does not match the evaluated configuration" >&2
      exit 65
    fi

    validate_property() {
      property="$1"
      expected="$2"
      actual="$(zfs get -H -o value "$property" "$dataset")"
      if [ "$actual" != "$expected" ]; then
        echo "TaskView ZFS property $property does not match the evaluated configuration" >&2
        exit 65
      fi
    }

    validate_property compression zstd
    validate_property atime off
    validate_property acltype posix
    validate_property xattr sa
    validate_property dnodesize auto
  '';
  validateState = pkgs.writeShellApplication {
    name = "taskview-validate-state";
    runtimeInputs = [
      config.boot.zfs.package
      pkgs.coreutils
      pkgs.util-linux
    ];
    text = validateStateScript;
  };
in
{
  options.shulker.system.modules.taskview = {
    enable = lib.mkEnableOption "TaskView household task management";
    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/taskview";
      description = "Dedicated state mount.";
    };
    dataset = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Dedicated ZFS dataset.";
    };
    datasetQuotaBytes = lib.mkOption {
      type = lib.types.ints.positive;
      default = 21474836480;
      description = "Expected quota in bytes.";
    };
    publicUrl = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Public web URL.";
    };
    apiPublicUrl = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Public API URL.";
    };
    mcpPublicUrl = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Public MCP endpoint.";
    };
    centrifugoPublicUrl = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Public notification WebSocket URL.";
    };
    oidcIssuer = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Pocket ID issuer configured during organization onboarding.";
    };
    trustProxy = lib.mkOption {
      type = lib.types.str;
      default = "false";
      description = "Express trust proxy policy; enable only for the verified Pangolin boundary.";
    };
    webPort = lib.mkOption {
      type = lib.types.port;
      default = 23242;
      description = "Loopback web port.";
    };
    apiPort = lib.mkOption {
      type = lib.types.port;
      default = 23243;
      description = "Loopback API port.";
    };
    mcpPort = lib.mkOption {
      type = lib.types.port;
      default = 23244;
      description = "Loopback MCP port.";
    };
    centrifugoPort = lib.mkOption {
      type = lib.types.port;
      default = 23245;
      description = "Loopback notification port.";
    };
    backUpData = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Create logical PostgreSQL backups for Borgmatic.";
    };
    images = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      readOnly = true;
      default = import ./images.nix;
      description = "Pinned images.";
    };
    validateStateScript = lib.mkOption {
      type = lib.types.lines;
      internal = true;
      readOnly = true;
    };
    validateStatePackage = lib.mkOption {
      type = lib.types.package;
      internal = true;
      readOnly = true;
    };
  };
  config = lib.mkIf cfg.enable {
    shulker.system.modules.taskview = {
      inherit validateStateScript;
      validateStatePackage = validateState;
    };
    assertions = [
      {
        assertion = lib.all (url: lib.hasPrefix "https://" url) [
          cfg.publicUrl
          cfg.apiPublicUrl
          cfg.mcpPublicUrl
          cfg.oidcIssuer
        ];
        message = "TaskView public URLs and issuer must use HTTPS.";
      }
      {
        assertion = lib.hasPrefix "wss://" cfg.centrifugoPublicUrl;
        message = "TaskView notifications require WSS.";
      }
      {
        assertion = cfg.dataset != "" && lib.hasPrefix "/" cfg.stateDir && cfg.stateDir != "/";
        message = "TaskView needs a dedicated dataset and absolute state directory.";
      }
      {
        assertion = !cfg.backUpData || config.shulker.system.modules.backup.enable;
        message = "TaskView backups require Borgmatic.";
      }
      {
        assertion =
          builtins.length (
            lib.unique [
              cfg.webPort
              cfg.apiPort
              cfg.mcpPort
              cfg.centrifugoPort
            ]
          ) == 4;
        message = "TaskView loopback ports must be distinct.";
      }
      {
        assertion = lib.all (image: lib.hasInfix "@sha256:" image) (builtins.attrValues cfg.images);
        message = "TaskView images must be pinned by digest.";
      }
    ];
    shulker.system.modules.containers.enable = true;
    environment.systemPackages = [ validateState ];
    fileSystems.${cfg.stateDir} = {
      device = cfg.dataset;
      fsType = "zfs";
      options = [ "nofail" ];
    };
    systemd.services.taskview-state = {
      description = "Validate and prepare TaskView state";
      unitConfig.RequiresMountsFor = cfg.stateDir;
      path = [ pkgs.coreutils ];
      script = ''
        ${validateState}/bin/taskview-validate-state
        install -d -m 0700 ${lib.escapeShellArg cfg.stateDir}/{postgres,backups}
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
    };
    services.onepassword-secrets.secrets.taskviewEnv = {
      reference = "op://Shulker/${config.networking.hostName}/TaskView/Environment";
      services = [
        "taskview-config"
        "taskview-compose"
      ];
      owner = "root";
      group = "root";
      mode = "0400";
    };
  };
}
