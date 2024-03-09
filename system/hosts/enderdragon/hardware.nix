{ config, lib, pkgs, modulesPath, ... }:

{
  imports =
    [ (modulesPath + "/installer/scan/not-detected.nix")
    ];

  boot.initrd.availableKernelModules = [ "nvme" "xhci_pci" "ahci" "usb_storage" "usbhid" "sd_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-amd" ];
  boot.extraModulePackages = [ ];

  fileSystems."/" =
    { device = "none";
      fsType = "tmpfs";
      options = [ "defaults" "size=16G" "mode=755" ];
    };

  fileSystems."/boot" =
    { device = "/dev/disk/by-uuid/5D35-05FA";
      fsType = "vfat";
    };

  fileSystems."/boot-fallback" =
    { device = "/dev/disk/by-uuid/5D35-7F32";
      fsType = "vfat";
    };

  fileSystems."/nix" =
    { device = "rpool/local/nix";
      fsType = "zfs";
      options = [ "zfsutil" ];
    };

  fileSystems."/nix/persist" =
    { device = "rpool/safe/persist";
      fsType = "zfs";
      options = [ "zfsutil" ];
      neededForBoot = true;
    };

  fileSystems."/secrets" =
    { device = "rpool/safe/secrets";
      fsType = "zfs";
      options = [ "zfsutil" ];
      neededForBoot = true;
    };

  swapDevices = [ ];

  networking.useDHCP = lib.mkDefault true;
  # networking.interfaces.enp5s0.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
