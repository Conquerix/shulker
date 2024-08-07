{ pkgs, ... }:

{
  imports = [ ./hardware.nix ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernel.sysctl."vm.max_map_count" = 2147483642;

  # For zfs.
  networking.hostId = "2118dc3b";

  # Disable this to try and solve the nework manager wait online failed after each rebuild.
  # Only on warden for now, but may go on common profile.
  systemd.network.wait-online.enable = false;
  boot.initrd.systemd.network.wait-online.enable = false;

  shulker = {
    profiles.server.enable = true;
    modules = {
      user.home = ./home.nix;
      docker.enable = true;
      impermanence.enable = true;
      ssh_server.enable = true;
      wireguard.enable = true;
      gitea = {
        enable = true;
        baseUrl = "shulker.fr";
        subDomain = "git";
        httpPort = 23231;
        stateDir = "/storage/flash/gitea";
        backupDir = "/storage/hdd/gitea/backup";
      };
      github-runner = {
        enable = true;
        owner = "The-InBetween";
        workDir = "/storage/nvme/github-runner";
      };
    };
  };
}