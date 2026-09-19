# Logical dumps are sufficient: all TaskView application state is in PostgreSQL.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.shulker.system.modules.taskview;
  manifest = pkgs.writeText "taskview-backup-manifest.json" (
    builtins.toJSON {
      format_version = 1;
      database = "taskview";
      postgres_major = 17;
      producer_revision = config.system.configurationRevision or "unrecorded";
      restore = "Restore with pg_restore --exit-on-error into an empty PostgreSQL 17 database; use matching images and the original ENCRYPTION_KEY.";
    }
  );
  backupPrepare = pkgs.writeShellApplication {
    name = "taskview-backup-prepare";
    runtimeInputs = [
      config.virtualisation.docker.package
      pkgs.coreutils
      pkgs.findutils
      pkgs.jq
      pkgs.util-linux
    ];
    text = "exec ${pkgs.bash}/bin/bash ${./backup.sh} ${lib.escapeShellArg "${cfg.stateDir}/backups"} /run/lock/taskview-maintenance.lock ${cfg.validateStatePackage}/bin/taskview-validate-state ${manifest}";
  };
in
{
  options.shulker.system.modules.taskview.backupPreparePackage = lib.mkOption {
    type = lib.types.package;
    readOnly = true;
    internal = true;
  };
  config = lib.mkIf cfg.enable {
    shulker.system.modules.taskview.backupPreparePackage = backupPrepare;
    environment.systemPackages = [ backupPrepare ];
    services.borgmatic.settings.commands = lib.mkIf cfg.backUpData [
      {
        before = "action";
        when = [ "create" ];
        run = [ "${backupPrepare}/bin/taskview-backup-prepare" ];
      }
    ];
    shulker.system.modules.backup.dirs = lib.mkIf cfg.backUpData [ "${cfg.stateDir}/backups" ];
    systemd.services.borgmatic = lib.mkIf cfg.backUpData {
      unitConfig.RequiresMountsFor = [ cfg.stateDir ];
      # Mount validation uses /dev/zfs inside the existing Borgmatic sandbox.
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
  };
}
