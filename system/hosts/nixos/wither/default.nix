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
      # SteamOS-like Steam Machine: boots into Gaming Mode, GNOME for "Switch to
      # Desktop". Pulls in the desktop profile + Steam (Proton-GE) itself.
      profiles.steam-machine = {
        enable = true;
        user = "conquerix";
        desktopSession = "gnome";
        # Nvidia-only: the monitor is plugged into the Nvidia card, so the dGPU
        # drives the display directly. No AMD GPU tuning needed.
        amdGpu = false;
      };
      modules = {
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
        # Nvidia-only: the dGPU renders and scans out to the monitor directly.
        # No PRIME hybrid/offload, so no cross-GPU frame copy (less latency, no
        # tearing). The AMD iGPU stays present but unused.
        nvidia.enable = true;
        sunshine.enable = true;
      };
    };
  };
}
