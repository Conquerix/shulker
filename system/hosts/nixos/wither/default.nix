{
  pkgs,
  ...
}:

{
  imports = [ ./hardware.nix ];

  boot.kernel.sysctl = {
    "vm.max_map_count" = 1048576;
  };

  boot.loader.systemd-boot = {
    enable = true;
    edk2-uefi-shell.enable = true; # used to find efi dev handle: https://search.nixos.org/options?channel=unstable&show=boot.loader.systemd-boot.windows.%3Cname%3E.efiDeviceHandle&from=0&size=50&sort=relevance&type=packages&query=boot.loader.systemd-boot.windows
    windows."win-11-entreprise" = {
      title = "Windows 11 Entreprise";
      efiDeviceHandle = "HD0b";
    };
  };
  boot.loader.efi.canTouchEfiVariables = true;

  programs.gamemode.enable = true;

  networking.hostId = "7fbe10c9";

  services.udev.extraRules = ''
    # Rules for Oryx web flashing and live training
    KERNEL=="hidraw*", ATTRS{idVendor}=="16c0", MODE="0664", GROUP="plugdev"
    KERNEL=="hidraw*", ATTRS{idVendor}=="3297", MODE="0664", GROUP="plugdev"

    # Keymapp Flashing rules for the Voyager
    SUBSYSTEMS=="usb", ATTRS{idVendor}=="3297", MODE:="0666", SYMLINK+="ignition_dfu"
  '';

  environment.systemPackages = with pkgs; [
    chromium
    keymapp
    obsidian
  ];

  programs.eden = {
    enable = true;
    enableCache = true; # Optional: Enable cache (see Cachix section)
  };

  shulker = {
    system = {
      profiles.desktop.enable = true;
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
        ollama = {
          enable = true;
          impermanence = true;
          acceleration = "cuda";
          host = "0.0.0.0";
        };
        nvidia = {
          enable = true;
          hybrid = {
            enable = true;
            offload = true;
            amdgpuBusId = "PCI:108:0:0";
            nvidiaBusId = "PCI:1:0:0";
          };
        };
      };
    };
    users.conquerix.enable = true;
  };
}
