{
  lib,
  pkgs,
  ...
}:

let
  # gamescope from pinned master: the 3.16.24 release has a cluster of
  # nested-backend bugs we hit on this box (game composited tiny at (0,0)
  # after closing the Steam overlay/QAM, input focus not returning to the
  # game, presentation stall after a fullscreen window resize). Master has
  # direct fixes: a563226d "do not forcefully snap focus windows to (0,0)",
  # 727c0856/dac83bb6 _NET_ACTIVE_WINDOW keyboard-focus fixes, 9dad5bd2
  # swapchain use-after-free. Drop back to pkgs.gamescope once a release
  # containing these ships in nixpkgs.
  gamescope-master = pkgs.gamescope.overrideAttrs (old: {
    version = "3.16.24-unstable-2026-07-13";
    src = pkgs.fetchFromGitHub {
      owner = "ValveSoftware";
      repo = "gamescope";
      rev = "16a44df7b4a067daf62a38d73d87a0a9cdca45a3";
      fetchSubmodules = true;
      hash = "sha256-lBmH3MOyG5/8Ogiyt/HFczy8QoeU3kOfOZ/C4fKUUTo=";
    };
    # Keep nixpkgs' packaging patches (*.patch: shader path, reaper path) but
    # drop its upstream-commit backports (*.diff) — they target 3.16.24 and
    # don't apply on master.
    patches = builtins.filter (
      p: lib.hasSuffix ".patch" (p.name or (builtins.baseNameOf p))
    ) old.patches;
    # Master dropped the glm/stb include-dir meson options (they are regular
    # dependencies now); the 3.16.24 recipe still passes them and meson hard
    # errors on unknown options.
    mesonFlags = builtins.filter (
      f: !(lib.hasPrefix "-Dglm_include_dir" f || lib.hasPrefix "-Dstb_include_dir" f)
    ) (old.mesonFlags or [ ]);
    # Master consumes glm/stb as unconditional meson wrap-git subprojects,
    # which can't download in the sandbox. Pre-seed them at the revisions
    # from subprojects/{glm,stb}.wrap and apply the packagefiles overlays
    # (the wrap patch_directory) that carry their meson build files.
    postPatch = (old.postPatch or "") + ''
      cp -r --no-preserve=mode ${
        pkgs.fetchFromGitHub {
          owner = "g-truc";
          repo = "glm";
          rev = "0af55ccecd98d4e5a8d1fad7de25ba429d60e863";
          hash = "sha256-GnGyzNRpzuguc3yYbEFtYLvG+KiCtRAktiN+NvbOICE=";
        }
      } subprojects/glm
      cp -r --no-preserve=mode subprojects/packagefiles/glm/. subprojects/glm/
      cp -r --no-preserve=mode ${
        pkgs.fetchFromGitHub {
          owner = "nothings";
          repo = "stb";
          rev = "5736b15f7ea0ffb08dd38af21067c314d6a3aae9";
          hash = "sha256-s2ASdlT3bBNrqvwfhhN6skjbmyEnUgvNOrvhgUSRj98=";
        }
      } subprojects/stb
      cp -r --no-preserve=mode subprojects/packagefiles/stb/. subprojects/stb/
    '';
  });
in
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
      # SteamOS session flags instead of plain -bigpicture: in -bigpicture
      # mode Steam raises its UI over the game inside gamescope's Xwayland
      # when the overlay/QAM opens but never refocuses the game on close —
      # permanent black "in-game" backdrop. -steamos3/-steampal make Steam
      # drive gamescope's window focus like on a Steam Deck (the bootstrap
      # re-adds -steamdeck/-pipewire itself in this mode).
      #
      # Backend: gamescope's default Wayland backend. Do NOT pair the SteamOS
      # flags with --backend sdl: Steam's display reconfiguration makes SDL
      # re-create its xdg_toplevel on a wl_surface that already has a buffer
      # committed (xdg_wm_base error 4), mutter kills the connection, and the
      # service crash-loops. The Wayland backend handles reconfig natively;
      # its "Compositor released us but we were not acquired" log spam is
      # benign (ValveSoftware/gamescope#1636).
      #
      # No --hdr-enabled (yet): mutter doesn't expose what gamescope needs
      # (bExposeHDRSupport: false) and the driver returns zero modifiers for
      # gamescope's 16-bit composite formats (AB48/XB48), so the flag delivers
      # no HDR while switching internal paths onto the broken formats. Retry
      # after gamescope/driver/mutter bumps.
      # The GNOME output stays in HDR/bt2100 (monitors.xml): counterintuitively
      # that is the SIGNAL-stable config on this cable/One Connect — HDR runs
      # DSC-compressed, while uncompressed SDR glitches at both 4K@120 and
      # 4K@165. Gamescope's own pipeline is then forced to SDR via the
      # hdr_enabled convar (ExecStartPost below): with it on, gamescope
      # composites into 16-bit formats the Nvidia driver returns zero DRM
      # modifiers for, and the screen goes permanently black the first time
      # compositing kicks in (opening the Steam overlay/QAM over a game).
      # Game HDR was never exposed anyway (bExposeHDRSupport: false); revisit
      # after driver/mutter bumps.
      # Known gamescope 3.16.24 nested-backend bugs and their operating rules:
      # resizing a fullscreen game window stalls its presentation permanently
      # (frozen image, audio continues) — so no --force-windows-fullscreen,
      # which force-resizes every game at map time. And after closing the
      # Steam overlay/QAM, gamescope loses the upscale transform for windows
      # smaller than the output and composites them tiny in the top-left
      # corner. Practical rule: run games at native 3840x2160 (no transform
      # to lose, no resize needed). Revisit both on gamescope bumps.
      ExecStart = "${gamescope-master}/bin/gamescope -W 3840 -H 2160 -r 165 --fullscreen --steam -- ${pkgs.steam}/bin/steam -gamepadui -steamos3 -steampal";
      # Runtime convar pins, applied once the control socket is up:
      # - hdr_enabled 0: keep the composite pipeline SDR (see above). Note
      #   Steam re-enables it when an HDR-capable game launches and the
      #   pipeline wedges; the durable half of that fix is the HDR toggle
      #   turned OFF in gaming mode Settings > Display (user-level setting).
      # - adaptive_sync_ignore_overlay 1: after the QAM closes, Steam's
      #   overlay layer keeps repainting invisibly; with VRR each repaint
      #   forces a commit decoupled from game frames — lingering judder
      #   (seen in Clair Obscur). Pace VRR commits on the game only.
      ExecStartPost = "${pkgs.writeShellScript "gamescope-convar-pins" ''
        for _ in $(seq 30); do
          if ${gamescope-master}/bin/gamescopectl hdr_enabled 0 2>/dev/null; then
            ${gamescope-master}/bin/gamescopectl adaptive_sync_ignore_overlay 1 2>/dev/null
            exit 0
          fi
          sleep 1
        done
        # Non-fatal: better an unpinned gamescope than a restart loop.
        exit 0
      ''}";
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

  # The session wrapper above pins the same package; this additionally puts
  # gamescope on PATH for manual/per-game use (`gamescope ... -- %command%`,
  # e.g. to override the session defaults for one title). capSysNice stays
  # off: setcap binaries can't run from Steam's bwrap sandbox.
  programs.gamescope = {
    enable = true;
    package = gamescope-master;
  };

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
