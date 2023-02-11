{pkgs, ... }:

{
  imports = [ ./hardware.nix ];

  hardware.tuxedo-keyboard.enable = true;

  environment.systemPackages = with pkgs; [
    #linuxKernel.packages.linux_6_0.tuxedo-keyboard
    (agda.withPackages (p: [ p.standard-library ]))
    ocaml
    julia
    jupyter
  ];

  services.emacs = {
	enable = true;
	install = true;
	##package = pkgs.emacs-gtk;
    package = with pkgs; ((emacsPackagesFor emacs-gtk).emacsWithPackages (epkgs: [ epkgs.tuareg epkgs.markdown-mode epkgs.markdown-preview-mode ]));
  };

  services.tor = {
  	enable = true;
  	client.enable = true;
  	torsocks.enable = true;
  };

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
      wireguard.client = {
        enable = true;
        clientIP = "192.168.10.3";
      };
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
    #nvme-egpu-external-display.configuration = {
    #  shulker.modules.nvidia  = {
    #    enable = true;
    #    hybrid = {
    #      enable = true;
    #      egpu = true;
    #      intelBusId = "PCI:0:2:0";
    #      nvidiaBusId = "PCI:2:0:0";
    #    };
    #  };
    #  system.nixos.tags = [ "external-display" ];
    #  hardware.nvidia.modesetting.enable = pkgs.lib.mkForce false;
    #  hardware.nvidia.powerManagement.enable = pkgs.lib.mkForce false;
    #  services.xserver.displayManager.gdm.wayland = false;
    #  services.xserver.config = pkgs.lib.mkOverride 0
    #  ''
    #Section "Module"
    #    Load           "modesetting"
    #EndSection
    #
    #Section "Device"
    #    Identifier     "Device0"
    #    Driver         "nvidia"
    #    BusID          "2:0:0"
    #    Option         "AllowEmptyInitialConfiguration"
    #    Option         "AllowExternalGpus" "True"
    #EndSection
    #'';
    #};
    #thunderbolt-egpu-external-display.configuration = {
    #  shulker.modules.nvidia  = {
    #    enable = true;
    #    hybrid = {
    #      enable = true;
    #      egpu = true;
    #      intelBusId = "PCI:0:2:0";
    #      nvidiaBusId = "PCI:5:0:0";
    #    };
    #  };
    #  system.nixos.tags = [ "external-display" ];
    #  hardware.nvidia.modesetting.enable = pkgs.lib.mkForce false;
    #  hardware.nvidia.powerManagement.enable = pkgs.lib.mkForce false;
    #  services.xserver.displayManager.gdm.wayland = false;
    #  services.xserver.config = pkgs.lib.mkOverride 0
    #  ''
    #Section "Module"
    #    Load           "modesetting"
    #EndSection
    #
    #Section "Device"
    #    Identifier     "Device0"
    #    Driver         "nvidia"
    #    BusID          "5:0:0"
    #    Option         "AllowEmptyInitialConfiguration"
    #    Option         "AllowExternalGpus" "True"
    #EndSection
    #'';
    #};
  };
}
