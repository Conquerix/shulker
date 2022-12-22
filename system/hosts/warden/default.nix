{ ... }:

{
  imports = [
    ./hardware.nix
    ./minecraft.nix
  ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # For zfs.
  networking.hostId = "2118dc3b";

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 23241 25501 ];
    allowedUDPPorts = [ 25501 ];
  };

  shulker = {
    modules = {
      user.home = ./home.nix;
      docker.enable = true;
      impermanence.enable = true;
      ssh_server = {
        enable = true;
      };
      wireguard.client = {
      	enable = true;
      	clientIP = "192.168.10.2";
      };
    };
  };
}
