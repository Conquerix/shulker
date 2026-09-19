{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.shulker.system.modules.actual-budget;
  validateStateScript = ''
    readonly state_dir=${lib.escapeShellArg cfg.stateDir}
    readonly dataset=${lib.escapeShellArg cfg.dataset}
    [ "$(findmnt --noheadings --output SOURCE --target "$state_dir")" = "$dataset" ] || {
      echo 'Actual state is not mounted from its dedicated dataset' >&2; exit 65;
    }
    [ "$(zfs get -Hp -o value quota "$dataset")" = ${lib.escapeShellArg (toString cfg.datasetQuotaBytes)} ] || {
      echo 'Actual dataset quota differs from configuration' >&2; exit 65;
    }
    for pair in compression:zstd atime:off acltype:posix xattr:sa dnodesize:auto; do
      [ "$(zfs get -H -o value "''${pair%%:*}" "$dataset")" = "''${pair#*:}" ] || {
        echo 'Actual dataset properties differ from configuration' >&2; exit 65;
      }
    done
  '';
  validateState = pkgs.writeShellApplication {
    name = "actual-budget-validate-state";
    runtimeInputs = [
      config.boot.zfs.package
      pkgs.util-linux
    ];
    text = validateStateScript;
  };
in
{
  options.shulker.system.modules.actual-budget = {
    enable = lib.mkEnableOption "Actual Budget household budgeting";
    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/actual-budget";
    };
    dataset = lib.mkOption {
      type = lib.types.str;
      default = "";
    };
    datasetQuotaBytes = lib.mkOption {
      type = lib.types.ints.positive;
      default = 10737418240;
    };
    publicUrl = lib.mkOption {
      type = lib.types.str;
      default = "";
    };
    oidcIssuer = lib.mkOption {
      type = lib.types.str;
      default = "";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 23246;
    };
    backUpData = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };
    image = lib.mkOption {
      type = lib.types.str;
      default = "ghcr.io/actualbudget/actual:26.9.0@sha256:552beab3dec8c93d46b8b9245612d63c3f123b8a45063a474f53e229b17621d3";
    };
    validateStateScript = lib.mkOption {
      type = lib.types.lines;
      readOnly = true;
      internal = true;
    };
    validateStatePackage = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      internal = true;
    };
  };
  config = lib.mkIf cfg.enable {
    shulker.system.modules.actual-budget = {
      inherit validateStateScript;
      validateStatePackage = validateState;
    };
    assertions = [
      {
        assertion = lib.hasPrefix "https://" cfg.publicUrl && lib.hasPrefix "https://" cfg.oidcIssuer;
        message = "Actual public URL and OIDC issuer require HTTPS.";
      }
      {
        assertion = cfg.dataset != "" && lib.hasPrefix "/" cfg.stateDir && cfg.stateDir != "/";
        message = "Actual requires a dedicated dataset and absolute state directory.";
      }
      {
        assertion = lib.hasInfix "@sha256:" cfg.image;
        message = "Actual image must be pinned by digest.";
      }
      {
        assertion = !cfg.backUpData || config.shulker.system.modules.backup.enable;
        message = "Actual backups require Borgmatic.";
      }
    ];
    shulker.system.modules.containers.enable = true;
    fileSystems.${cfg.stateDir} = {
      device = cfg.dataset;
      fsType = "zfs";
      options = [ "nofail" ];
    };
    environment.systemPackages = [ validateState ];
    systemd.services.actual-budget-state = {
      description = "Validate and prepare Actual Budget state";
      unitConfig.RequiresMountsFor = cfg.stateDir;
      path = [ pkgs.coreutils ];
      script = ''
        ${validateState}/bin/actual-budget-validate-state
        install -d -m 0700 ${lib.escapeShellArg cfg.stateDir}/data
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
    };
    services.onepassword-secrets.secrets.actualBudgetEnv = {
      reference = "op://Shulker/${config.networking.hostName}/Actual Budget/Environment";
      services = [ "actual-budget-compose" ];
      owner = "root";
      group = "root";
      mode = "0400";
    };
    shulker.system.secretPreflight.schemas.actualBudgetEnv = {
      format = "dotenv";
      exactKeys = lib.genAttrs [ "ACTUAL_OPENID_CLIENT_ID" "ACTUAL_OPENID_CLIENT_SECRET" ] (_: {
        minLength = 1;
        pattern = "^.+$";
      });
    };
  };
}
