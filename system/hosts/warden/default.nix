{ ... }:

{
  imports = [ ./hardware.nix ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  
  networking.hostId = "2118dc3b";

  shulker = {
    modules = {
      user.home = ./home.nix;
      impermanence.enable = true;
      ssh_server = {
        enable = true;
        tor = {
          enable = false;
          port = 45022;
        };
      };
      wireguard.client = {
      	enable = true;
      	clientIP = "192.168.10.2";
      };
    };
  };
}
