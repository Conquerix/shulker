{
  pkgs,
  ...
}:

{
  imports = [ ./hardware.nix ];

  boot.kernel.sysctl = {
    "vm.max_map_count" = 1048576;
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  programs.gamemode.enable = true;

  # GDM auto-login for conquerix
  services.xserver.displayManager.gdm.autoLogin.enable = true;
  services.xserver.displayManager.gdm.autoLogin.user = "conquerix";

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
    users.conquerix.enable = true;
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
        sunshine.enable = true;
      };
    };
  };
}
