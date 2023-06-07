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
      user.home = ./home.nix;
      impermanence = {
        enable = true;
        home = true;
      };
      yubikey.enable = true;
      ssh_server.enable = true;
      };
    profiles = {
      tvbox = {
        enable = true;
      };
    };
  };
}
