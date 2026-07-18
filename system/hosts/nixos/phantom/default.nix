{ ... }:

{
  imports = [ ./hardware.nix ];

  hardware = {
    #tuxedo-keyboard.enable = true;
    tuxedo-rs = {
      enable = true;
      tailor-gui.enable = true;
    };
  };

  boot.kernel.sysctl = {
    "vm.max_map_count" = 1048576;
  };

  boot.loader = {
    efi = {
      canTouchEfiVariables = true;
      efiSysMountPoint = "/boot";
    };
    grub = {
      enable = true;
      devices = [ "nodev" ];
      efiSupport = true;
    };
  };

  shulker = {
    users.conquerix.enable = true;
    system = {
      profiles.desktop = {
        enable = true;
        laptop = true;
      };
      modules = {
        steam = {
          enable = true;
          protonGE = true;
        };
        impermanence = {
          enable = true;
          home = true;
        };
        yubikey.enable = true;
      };
    };
  };
}
