{ config, lib, ... }:
let
  cfg = config.shulker.system.modules.kitchenowl;
  runtime = "${cfg.runtimePackage}/bin/kitchenowl-runtime";
in
{
  config = lib.mkIf (cfg.enable && cfg.backUpData) {
    services.borgmatic.settings.commands = [
      {
        before = "action";
        when = [ "create" ];
        run = [ "${runtime} backup" ];
      }
      {
        after = "action";
        when = [ "create" ];
        states = [
          "finish"
          "fail"
        ];
        run = [ "${runtime} cleanup" ];
      }
      {
        after = "error";
        when = [ "create" ];
        run = [ "${runtime} cleanup" ];
      }
    ];
    shulker.system.modules.backup.dirs = [ "${cfg.stateDir}/.zfs/snapshot/borgmatic/data" ];
    systemd.services.borgmatic = {
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
  };
}
