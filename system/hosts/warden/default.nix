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
      ssh_server = {
        enable = true;
        tor = {
          enable = true;
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
