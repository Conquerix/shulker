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

  # Nvidia-only display path: keep the AMD iGPU out of the picture entirely.
  # As a second DRM device it is a source of wrong-GPU bugs (gamescope/mutter
  # binding the iGPU, Vulkan enumerating it first). Drop this line to get the
  # iGPU back (e.g. to retry AMD scanout).
  boot.blacklistedKernelModules = [ "amdgpu" ];

  # Diagnostic: the S95F image glitches like a broken signal. Force the
  # conservative HDMI signal mode (plain TMDS instead of HDMI 2.1 FRL, 8-bit
  # instead of deep color) — the same mode the AMD iGPU used. Caps output at
  # 4K@60. If the image is clean with this, the glitching is FRL link quality
  # (cable / One Connect box); remove both params to get 4K@120+/VRR back.
  boot.kernelParams = [
    "nvidia_modeset.disable_hdmi_frl=1"
    "nvidia_modeset.hdmi_deepcolor=0"
  ];

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
        # Nvidia-only: the TV is plugged into the Nvidia card's HDMI 2.1 port
        # and the dGPU drives the display directly, so no AMD GPU tuning.
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
        # Nvidia-only: the dGPU renders and scans out to the TV directly over
        # HDMI 2.1 — needed for 4K@120+/VRR on the S95F, which amdgpu cannot do
        # (no HDMI 2.1 on the open driver). The earlier direct-scanout attempt
        # predated driver 595/explicit sync and ran with the iGPU still active;
        # both are addressed now (amdgpu blacklisted above). PRIME bus IDs for
        # reference if hybrid is ever needed again: amdgpu PCI:108:0:0,
        # nvidia PCI:1:0:0.
        nvidia.enable = true;
        sunshine.enable = true;
      };
    };
  };
}
