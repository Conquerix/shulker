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
    hetznerStorageBoxAccount = lib.mkOption {
      type = types.str;
      description = "Hetzner storagebox account of the machine.";
    };
  };

  config = mkIf cfg.enable {
    programs.ssh.knownHosts."hetzner-storage-box" = {
      hostNames = [ "[${cfg.hetznerStorageBoxAccount}.your-storagebox.de]:23" ];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIICf9svRenC/PLKIL9nk6K/pxQgoiFC41wTNvoIncOxs";
    };

    services.borgmatic = {
      enable = true;
      settings = {
        ssh_command = "ssh -i ${config.services.onepassword-secrets.secrets.sshed25519HostKey.path}";
        encryption_passcommand = "cat ${config.services.onepassword-secrets.secrets.hetznerBorgPassword.path}";
        source_directories = cfg.dirs;
        repositories = [
          {
            label = "Hetzner Storage Box";
            path = "ssh://${cfg.hetznerStorageBoxAccount}@${cfg.hetznerStorageBoxAccount}.your-storagebox.de:23/./borg-repository";
          }
        ];
        keep_daily = 7;
        keep_weekly = 4;
        keep_monthly = 6;
        checks = [
          {
            name = "repository";
            frequency = "1 week";
          }
          {
            name = "archives";
            frequency = "1 month";
          }
        ];
      };
    };
    systemd.services.borgmatic.serviceConfig.StateDirectory = "borgmatic";
    environment.persistence = mkIf config.shulker.system.modules.impermanence.enable {
      "/nix/persist".directories = [ "/var/lib/borgmatic" ];
    };
    services.onepassword-secrets.secrets.hetznerBorgPassword = {
      reference = "op://Shulker/${config.networking.hostName}/Backups/Hetzner StorageBox borgbackup password";
      services = [ "borgmatic" ];
    };
  };
}
