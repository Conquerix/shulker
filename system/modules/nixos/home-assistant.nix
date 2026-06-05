{
  config,
  lib,
  ...
}:

with lib;
let
  cfg = config.shulker.system.modules.home-assistant;
in
{
  options.shulker.system.modules.home-assistant = {
    enable = mkEnableOption "Enable Home Assistant";
    impermanence = mkEnableOption "Enable impermanence for Home Assistant.";
    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/home-assistant";
      description = "State Directory for Home Assistant config and data.";
    };
    timezone = mkOption {
      type = types.str;
      default = config.time.timeZone;
      description = "Timezone for Home Assistant container (TZ environment variable).";
    };
  };

  config = mkIf cfg.enable {

    virtualisation.oci-containers.containers."home-assistant" = {
      image = "ghcr.io/home-assistant/home-assistant:stable";
      privileged = true;
      volumes = [
        "${cfg.stateDir}:/config:rw"
        "/run/dbus:/run/dbus:ro"
      ];
      environment = {
        TZ = cfg.timezone;
      };
      log-driver = "journald";
      extraOptions = [
        "--network=host"
        "--cap-add=NET_ADMIN"
        "--cap-add=NET_RAW"
      ];
    };

    environment.persistence = mkIf cfg.impermanence {
      "/nix/persist".directories = [
        {
          directory = cfg.stateDir;
          mode = "u=rwx,g=rx,o=";
        }
      ];
    };

    shulker.system.modules.backup.dirs = [ cfg.stateDir ];
  };
}
