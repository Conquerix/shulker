{
  lib,
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

  # TV-couch usability: log straight into GNOME and start Steam in Big Picture.
  # The desktop profile disables autologin (multi-user default), so force it
  # back on for this single-seat living-room box.
  services.displayManager.autoLogin = {
    enable = lib.mkForce true;
    user = "conquerix";
  };
  environment.etc."xdg/autostart/steam-bigpicture.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=Steam (Big Picture)
    Exec=steam -bigpicture
  '';

  # GameMode lets games request CPU/GPU performance tweaks on the fly
  # (was provided by the steam-machine profile before).
  programs.gamemode.enable = true;

  shulker = {
    users.conquerix.enable = true;
    system = {
      # Normal GNOME desktop. The Jovian steam-machine profile is parked for
      # now: gamescope glitches on Nvidia scanout (GNOME on the same driver,
      # cable and mode is clean, so it's gamescope-specific). Steam runs in
      # Big Picture on the desktop instead (autologin + autostart above).
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
