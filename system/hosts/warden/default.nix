{ pkgs, ... }:

{
  imports = [ ./hardware.nix ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernel.sysctl."vm.max_map_count" = 2147483642;

  # For zfs.
  networking.hostId = "2118dc3b";

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 8096 1900 ];
    allowedUDPPorts = [ 8096 1900 ];
  };

  shulker = {
    profiles.server.enable = true;
    modules = {
      user.home = ./home.nix;
      impermanence.enable = true;
      wireguard.enable = true;
      jellyfin = {
        enable = true;
        baseUrl = "shulker.link";
        subDomain = "vod";
        stateDir = "/storage/flash/jellyfin";
      };
      jellyseerr = {
        enable = true;
        baseUrl = "shulker.link";
      };
      sonarr = {
        enable = true;
        baseUrl = "shulker.link";
        stateDir = "/storage/flash/sonarr";
      };
      radarr = {
        enable = true;
        baseUrl = "shulker.link";
        stateDir = "/storage/flash/radarr";
      };
      prowlarr = {
        enable = true;
        baseUrl = "shulker.link";
      };
    };
  };
}