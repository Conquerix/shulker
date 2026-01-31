{
  config,
  lib,
  ...
}:

with lib;
let
  cfg = config.shulker.system.modules.backup;

  repository =
    with lib.types;
    submodule {
      options = {
        path = lib.mkOption {
          type = str;
          description = ''
            Path to the repository
          '';
        };
        label = lib.mkOption {
          type = str;
          description = ''
            Label to the repository
          '';
        };
        encryption = lib.mkOption {
          type = str;
          description = ''
            Encryption mode of the repository
          '';
        };
      };
    };
in
{
  options.shulker.system.modules.backup = {
    enable = mkEnableOption "Enable backups using borgmatic";
    dirs = lib.mkOption {
      type = listOf str;
      default = [ ];
      description = "List of directories and files to backup.";
    };
  };

  options.services.borgmatic.settings.repositories = lib.mkForce lib.mkOption {
    type = listOf repository;
    default = [ ];
  };

  config = mkIf cfg.enable {
    services.borgmatic = {
      enable = true;
      settings = {
        ssh_command = "ssh -i ${config.services.onepassword-secrets.secrets.sshed25519HostKey.path}";
        encryption_passcommand = "cat ${config.services.onepassword-secrets.secrets.hetznerBorgPassword.path}";
        source_directories = cfg.dirs;
        repositories = [
          {
            label = "Hetzner Storage Box";
            path = "ssh://u515568-sub2@u515568-sub2.your-storagebox.de:23/./borg-repository";
            encryption = "repokey";
          }
        ];
      };
    };
    services.onepassword-secrets.secrets.hetznerBorgPassword = {
      reference = "op://Shulker/${config.networking.hostName}/Hetzner StorageBox borgbackup password";
      services = [ "borgmatic" ];
    };
  };
}
