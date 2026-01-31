{
  config,
  lib,
  ...
}:

with lib;
let
  cfg = config.shulker.system.modules.backup;
in
{
  options.shulker.system.modules.backup = {
    enable = mkEnableOption "Enable backups using borgmatic";
    dirs = lib.mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "List of directories and files to backup.";
    };
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
          }
        ];
      };
    };
    services.onepassword-secrets.secrets.hetznerBorgPassword = {
      reference = "op://Shulker/${config.networking.hostName}/Hetzner StorageBox borgbackup password";
      #services = [ "borgmatic" ];
    };
  };
}
