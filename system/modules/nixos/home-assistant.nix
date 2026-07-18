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
    openFirewall = mkEnableOption "open Home Assistant's LAN firewall ports";
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

    networking.firewall = mkIf cfg.openFirewall {
      enable = true;
      allowedTCPPorts = [
        8123
        21064
      ];
    };

    virtualisation.oci-containers.containers."home-assistant" = {
      image = "ghcr.io/home-assistant/home-assistant:stable@sha256:1476924357b46e80735c13e94232ba5c853cac052e9df4bb28d50fa56348097b";
      privileged = true;
      volumes = [
        "${cfg.stateDir}:/config:rw"
        "/run/dbus:/run/dbus:ro"
        "/dev:/dev"
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
