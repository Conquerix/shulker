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

  # Steam runs as a supervised user service instead of an xdg autostart entry.
  # Restart=always gives SteamOS semantics: any exit — crash or quit —
  # relaunches Big Picture. on-failure is not enough: gamescope exits 0 even
  # when Steam aborts underneath it ("Primary child shut down!"). GNOME
  # imports DISPLAY/WAYLAND_DISPLAY into the user manager before
  # graphical-session.target goes active, so the session env is available.
  #
  # Big Picture is wrapped in *nested* gamescope (SteamOS gaming mode as a
  # fullscreen GNOME window): every game automatically runs inside gamescope's
  # embedded Xwayland — upscaling, frame caps, HDR — no per-game launch
  # options needed. Nested = Wayland backend; GNOME keeps the DRM connector,
  # so this sidesteps the gamescope-on-Nvidia scanout glitching that parked
  # Jovian. VRR is mutter's job here (gamescope VRR flags are inert nested).
  # If steamwebhelper flickers inside gamescope, drop the gamescope wrapper
  # from ExecStart and use per-game gamescope launch options instead.
  systemd.user.services.steam-bigpicture = {
    description = "Steam (Big Picture)";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    serviceConfig = {
      # Raw pkgs.steam, NOT the programs.steam wrapper: the wrapper preloads
      # extest, whose XTEST shim panics and aborts Steam inside gamescope's
      # Xwayland (XTestFakeRelativeMotionEvent -> Rust panic_cannot_unwind).
      # gamescope handles XTEST for Steam Input natively, so extest is only
      # needed on the plain GNOME desktop, where it stays enabled. Proton-GE
      # still resolves via STEAM_EXTRA_COMPAT_TOOLS_PATHS (session var from
      # the steam module).
      #
      # --force-composition: without it, nested gamescope "bypasses" (forwards
      # the game buffer straight to mutter) and re-composites when the Steam
      # overlay/QAM opens; the switch back desyncs explicit-sync buffer
      # tracking on Nvidia ("Compositor released us but we were not acquired")
      # and the game goes permanently black. Always compositing avoids the
      # transition; the extra blit is nothing at 4K on this GPU.
      #
      # No --hdr-enabled (yet): mutter doesn't expose what gamescope needs
      # (bExposeHDRSupport: false) and the driver returns zero modifiers for
      # gamescope's 16-bit composite formats (AB48/XB48), so the flag delivers
      # no HDR while switching internal paths onto the broken formats. Retry
      # after gamescope/driver/mutter bumps.
      ExecStart = "${pkgs.gamescope}/bin/gamescope -W 3840 -H 2160 -r 120 --force-composition --fullscreen --steam -- ${pkgs.steam}/bin/steam -bigpicture";
      Restart = "always";
      RestartSec = 5;
    };
  };

  # Console-mode GNOME: no blanking, locking, or notification popups over
  # games — screen-off is the TV's/Steam's job, like a real console. These are
  # defaults (system db); changes made in Settings on the box still win.
  programs.dconf.profiles.user.databases = [
    {
      settings = {
        # VRR is behind a mutter experimental flag (fine on Nvidia with
        # explicit sync). Per-monitor toggle then appears in Settings >
        # Displays and has to be flipped once.
        "org/gnome/mutter".experimental-features = [ "variable-refresh-rate" ];
        "org/gnome/desktop/session".idle-delay = lib.gvariant.mkUint32 0;
        "org/gnome/desktop/screensaver".lock-enabled = false;
        "org/gnome/settings-daemon/plugins/power".sleep-inactive-ac-type = "nothing";
        "org/gnome/desktop/notifications".show-banners = false;
        # Couch-readable UI at TV distance.
        "org/gnome/desktop/interface".text-scaling-factor = 1.25;
      };
    }
  ];

  # The session wrapper above pins its own pkgs.gamescope; this additionally
  # puts gamescope on PATH for manual/per-game use (`gamescope ... --
  # %command%`, e.g. to override the session defaults for one title).
  # capSysNice stays off: setcap binaries can't run from Steam's bwrap
  # sandbox.
  programs.gamescope.enable = true;

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
