{config, ... }:

{
  imports = [ ./hardware.nix ];

  environment.systemPackages = [
    config.pkgs.linuxKernel.packages.linux_6_0.tuxedo-keyboard
  ];

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
      onepassword.enable = true;
      gnomeConfig = {
        enable = true;
        eyeCandy = true;
        moreUtils = true;
      };
      steam = {
        enable = true;
        protonGE = true;
      };
      user.home = ./home.nix;
      impermanence = {
        enable = true;
        home = true;
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
