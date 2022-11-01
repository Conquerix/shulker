{pkgs, ... }:

{
  imports = [ ./hardware.nix ];

  hardware.tuxedo-keyboard.enable = true;

  environment.systemPackages = [
    pkgs.linuxKernel.packages.linux_6_0.tuxedo-keyboard
    pkgs.prismlauncher
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
      _1password = {
        enable = true;
        users = [ "conquerix" ];
      };
      gnome = {
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
      yubikey.enable = true;
    };
    profiles = {
      desktop = {
        enable = true;
        laptop = true;
      };
    };
  };

  specialisation = {
    nvme-egpu.configuration = {
      shulker.modules.nvidia  = {
        enable = true;
        hybrid = {
          enable = true;
          egpu = true;
          intelBusId = "PCI:0:2:0";
          nvidiaBusId = "PCI:2:0:0";
        };
      };
    };
    thunderbolt-egpu.configuration = {
      shulker.modules.nvidia  = {
        enable = true;
        hybrid = {
          enable = true;
          egpu = true;
          intelBusId = "PCI:0:2:0";
          nvidiaBusId = "PCI:5:0:0";
        };
      };
    };
  };
}
