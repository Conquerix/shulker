{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.shulker.system.modules.kitchenowl;
  validateStateScript = ''
    readonly state_dir=${lib.escapeShellArg cfg.stateDir}
    readonly dataset=${lib.escapeShellArg cfg.dataset}
    [ "$(findmnt --noheadings --output SOURCE --target "$state_dir")" = "$dataset" ] || {
      echo 'KitchenOwl state is not mounted from its dedicated dataset' >&2; exit 65;
    }
    [ "$(zfs get -Hp -o value quota "$dataset")" = ${lib.escapeShellArg (toString cfg.datasetQuotaBytes)} ] || {
      echo 'KitchenOwl dataset quota differs from configuration' >&2; exit 65;
    }
    for pair in compression:zstd atime:off acltype:posix xattr:sa dnodesize:auto; do
      [ "$(zfs get -H -o value "''${pair%%:*}" "$dataset")" = "''${pair#*:}" ] || {
        echo 'KitchenOwl dataset properties differ from configuration' >&2; exit 65;
      }
    done
  '';
  validateState = pkgs.writeShellApplication {
    name = "kitchenowl-validate-state";
    runtimeInputs = [
      config.boot.zfs.package
      pkgs.util-linux
    ];
    text = validateStateScript;
  };
in
{
  options.shulker.system.modules.kitchenowl = {
    enable = lib.mkEnableOption "KitchenOwl household groceries and recipes";
    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/kitchenowl";
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
      default = 23247;
    };
    backUpData = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };
    image = lib.mkOption {
      type = lib.types.str;
      default = "tombursch/kitchenowl:v0.7.10@sha256:bd821a41b8cb27fd7fcf429acd1fc67e9f889485a2cd1193d68c2d804a8e1bef";
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
    shulker.system.modules.kitchenowl = {
      inherit validateStateScript;
      validateStatePackage = validateState;
    };
    assertions = [
      {
        assertion = lib.hasPrefix "https://" cfg.publicUrl && lib.hasPrefix "https://" cfg.oidcIssuer;
        message = "KitchenOwl public URL and OIDC issuer require HTTPS.";
      }
      {
        assertion = cfg.dataset != "" && lib.hasPrefix "/" cfg.stateDir && cfg.stateDir != "/";
        message = "KitchenOwl requires a dedicated dataset and absolute state directory.";
      }
      {
        assertion = lib.hasInfix "@sha256:" cfg.image;
        message = "KitchenOwl image must be pinned by digest.";
      }
      {
        assertion = !cfg.backUpData || config.shulker.system.modules.backup.enable;
        message = "KitchenOwl backups require Borgmatic.";
      }
    ];
    shulker.system.modules.containers.enable = true;
    fileSystems.${cfg.stateDir} = {
      device = cfg.dataset;
      fsType = "zfs";
      options = [ "nofail" ];
    };
    environment.systemPackages = [ validateState ];
    systemd.services.kitchenowl-state = {
      description = "Validate and prepare KitchenOwl state";
      unitConfig.RequiresMountsFor = cfg.stateDir;
      path = [ pkgs.coreutils ];
      script = ''
        ${validateState}/bin/kitchenowl-validate-state
        install -d -m 0700 ${lib.escapeShellArg cfg.stateDir}/data
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
    };
    services.onepassword-secrets.secrets.kitchenowlEnv = {
      reference = "op://Shulker/${config.networking.hostName}/KitchenOwl/Environment";
      services = [ "kitchenowl-compose" ];
      owner = "root";
      group = "root";
      mode = "0400";
    };
    shulker.system.secretPreflight.schemas.kitchenowlEnv = {
      format = "dotenv";
      exactKeys =
        lib.genAttrs [ "OIDC_CLIENT_ID" "OIDC_CLIENT_SECRET" ] (_: {
          minLength = 1;
          pattern = "^.+$";
        })
        // {
          JWT_SECRET_KEY = {
            minLength = 64;
            pattern = "^[0-9a-f]+$";
          };
        };
    };
  };
}
