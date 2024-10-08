{pkgs, ... }:

{
  imports = [ ./hardware.nix ];

  hardware = {
    #tuxedo-keyboard.enable = true;
    tuxedo-rs = {
    	enable = true;
    	tailor-gui.enable = true;
    };
  };

  boot.kernel.sysctl = { "vm.max_map_count" = 1048576; };

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
      wireguard.enable = true;
      docker.enable = true;
    };
    profiles = {
      desktop = {
        enable = true;
        laptop = true;
      };
    };
  };
}
