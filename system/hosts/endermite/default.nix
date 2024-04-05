{pkgs, ... }:

{
  imports = [ ./hardware.nix ];

  boot.loader = {
  efi = {
    canTouchEfiVariables = true;
    efiSysMountPoint = "/boot";
    };
  grub = {
    enable = true;
    devices = ["nodev"];
    efiSupport = true;
    };
  };

  shulker = {
    modules = {
      _1password = {
        enable = true;
        users = [ "conquerix" ];
      };
      gnome.enable = true;
      ssh_server.enable = true;
      user.home = ./home.nix;
      impermanence = {
        enable = true;
        home = true;
      };
      yubikey.enable = true;
      wireguard.client = {
        enable = true;
        clientIP = "192.168.10.8";
      };
    };
    profiles = {
      desktop = {
        enable = true;
        laptop = true;
      };
    };
  };
}
