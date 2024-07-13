{ pkgs, ... }:

{
  imports = [ ./hardware.nix ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernel.sysctl."vm.max_map_count" = 2147483642;

  # For zfs.
  networking.hostId = "2118dc3b";

  shulker = {
    profiles.server.enable = true;
    modules = {
      user.home = ./home.nix;
      docker.enable = true;
      impermanence.enable = true;
      ssh_server.enable = true;
      wireguard.enable = true;
      authelia = {
        enable = true;
        baseUrl = "shulker.fr";
        subDomain = "auth";
        port = 23233;
        stateDir = "/storage/flash/authelia";
      };
      gitea = {
        enable = true;
        baseUrl = "shulker.fr";
        subDomain = "git";
        httpPort = 23231;
        stateDir = "/storage/flash/gitea";
        backupDir = "/storage/hdd/gitea/backup";
      };
      jenkins = {
        enable = true;
        baseUrl = "shulker.fr";
        subDomain = "ci";
        httpPort = 23232;
        stateDir = "/storage/flash/jenkins";
      };
    };
  };
}