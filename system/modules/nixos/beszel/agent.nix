{
  config,
  lib,
  ...
}:

with lib;
let
  cfg = config.shulker.system.modules.beszel.agent;
in
{
  options.shulker.system.modules.beszel.agent = {
    enable = mkEnableOption "Enable beszel agent service.";
    impermanence = mkEnableOption "Enable impermanence.";
    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/beszel/agent";
      description = "State Directory.";
    };
    hubEndpoint = mkOption {
      type = types.str;
      description = "URL of the Beszel hub.";
    };
    extraFilesystems = mkOption {
      type = types.str;
      default = "/nix";
      description = "Comma separated list of extra filesystems to monitor";
    };
  };

  config = mkIf cfg.enable {

    users.groups.beszel-agent = { };
    users.users.beszel-agent = {
      isSystemUser = true;
      group = "beszel-agent";
    };
    systemd.tmpfiles.rules = [ "d ${cfg.stateDir} 0700 beszel-agent beszel-agent - -" ];

    services.beszel.agent = {
      enable = true;
      smartmon.enable = true;
      environment = {
        KEY_FILE = config.services.onepassword-secrets.secrets.beszelAgentKeyFile.path;
        TOKEN_FILE = config.services.onepassword-secrets.secrets.beszelAgentTokenFile.path;
        DATA_DIR = cfg.stateDir;
        EXTRA_FILESYSTEMS = cfg.extraFilesystems;
        HUB_URL = cfg.hubEndpoint;
      };
    };

    systemd.services.beszel-agent.serviceConfig.DynamicUser = mkForce false;

    environment = mkIf cfg.impermanence {
      persistence."/nix/persist".directories = [
        {
          directory = "${cfg.stateDir}";
          mode = "u=rwx,g=,o=";
          user = "beszel-agent";
          group = "beszel-agent";
        }
      ];
    };

    shulker.system.modules.backup.dirs = [ cfg.stateDir ];

    services.onepassword-secrets.secrets.beszelAgentKeyFile = {
      reference = "op://Shulker/${config.networking.hostName}/Beszel/Beszel Agent Key";
      services = [ "beszel-agent" ];
      owner = "beszel-agent";
    };

    services.onepassword-secrets.secrets.beszelAgentTokenFile = {
      reference = "op://Shulker/${config.networking.hostName}/Beszel/Beszel Agent Token";
      services = [ "beszel-agent" ];
      owner = "beszel-agent";
    };
  };
}
