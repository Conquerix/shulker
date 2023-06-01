{pkgs, ... }:

{
  imports = [ ./hardware.nix ];

  hardware = {
    tuxedo-keyboard.enable = true;
  };

  boot.kernel.sysctl = { "vm.max_map_count" = 1048576; };

  services.tor = {
  	enable = true;
  	client.enable = true;
  	torsocks.enable = true;
  };

  programs.wshowkeys.enable = true;

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
        clientIP = "192.168.10.3";
        #vpn = true;
      };
      docker.enable = true;
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
          offload = true;
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
          offload = true;
          intelBusId = "PCI:0:2:0";
          nvidiaBusId = "PCI:5:0:0";
        };
      };
    };
    egpu-external-display.configuration = {
      system.nixos.tags = [ "external-display" ];
      boot.kernelParams = [ "module_blacklist=i915" ];
      hardware.nvidia.modesetting.enable = pkgs.lib.mkForce false;
      hardware.nvidia.powerManagement.enable = pkgs.lib.mkForce false;
      shulker.modules.nvidia  = {
        enable = true;
      };
    };
  };
}
