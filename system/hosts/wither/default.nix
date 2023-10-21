{pkgs, lib, ... }:

{
  imports = [ ./hardware.nix ];


  boot.kernel.sysctl = { "vm.max_map_count" = 1048576; };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  programs.gamemode.enable = true;

  services.xserver.displayManager.gdm.wayland = lib.mkForce false;

  #environment.sessionVariables = {
  #  # If your cursor becomes invisible
  #  WLR_NO_HARDWARE_CURSORS = "1";
  #  # Hint electron apps to use wayland
  #  NIXOS_OZONE_WL = "1";
  #};

  shulker = {
    modules = {
      _1password = {
        enable = true;
        users = [ "conquerix" ];
      };
      gnome = {
        enable = true;
      };
      steam = {
        enable = true;
        protonGE = true;
      };
      user.home = ./home.nix;
      impermanence = {
        enable = true;
        home = true;
        docker = true;
      };
      yubikey.enable = true;
      wireguard.client = {
        enable = true;
        clientIP = "192.168.10.6";
        #vpn = true;
      };
      docker.enable = true;
      #encrypted_dns.enable=true;
      nvidia  = {
        enable = true;
        #hybrid = {
        #  enable = true;
        #  offload = true;
        #  amdgpuBusId = "PCI:12:0:0";
        #  nvidiaBusId = "PCI:1:0:0";
        #};
      };
    };
    profiles = {
      desktop = {
        enable = true;
      };
    };
  };
}
