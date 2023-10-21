{ pkgs, ... }:

{
  imports = [
    ./hardware.nix
#    ./minecraft.nix
#	./turbopilot.nix
  ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernel.sysctl."vm.max_map_count" = 2147483642;

  # For zfs.
  networking.hostId = "2118dc3b";

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 23080 5657 24480 26000 27000 30080 30443 5900 50443 50080 ];
    allowedUDPPorts = [ 25566 25568 26001 ];
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
