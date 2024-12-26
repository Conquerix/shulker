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
    allowedTCPPorts = [ 8096 ];
  };

  services.nginx = {
    enable = true;
    virtualHosts."jellyfin-tailnet" = {
      serverName = "vod.shulker.link";
      forceSSL = true;
      useACMEHost = "shulker.link";
      listenAddresses = [ "0.0.0.0" ];
      locations."/" = {
        proxyWebsockets = true;
        proxyPass = "http://127.0.0.1:8096";
        extraConfig = ''
          proxy_busy_buffers_size   512k;
          proxy_buffers   4 512k;
          proxy_buffer_size   256k;
        '';
      };
    };
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
        subDomain = "vod.internal";
        stateDir = "/storage/flash/jellyfin";
      };
    };
  };
}