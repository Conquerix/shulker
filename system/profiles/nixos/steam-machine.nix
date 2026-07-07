# Turns a regular desktop into a SteamOS-like "Steam Machine".
#
# Powered by Jovian-NixOS (https://github.com/Jovian-Experiments/Jovian-NixOS).
# The machine boots straight into Steam Gaming Mode (gamescope session) and can
# switch to the regular GNOME desktop from Steam's power menu ("Switch to Desktop").
#
# This profile builds on top of the `desktop` profile (for the desktop fallback
# session) and the `steam` module (for Proton-GE handling).
{
  config,
  lib,
  ...
}:

with lib;
let
  cfg = config.shulker.system.profiles.steam-machine;
in
{
  options.shulker.system.profiles.steam-machine = {
    enable = mkEnableOption "SteamOS-like Steam Machine (Jovian) profile";

    user = mkOption {
      type = types.str;
      default = "conquerix";
      description = "User that Gaming Mode (gamescope session) runs as.";
    };

    autoStart = mkOption {
      type = types.bool;
      default = true;
      description = "Boot straight into Steam Gaming Mode.";
    };

    desktopSession = mkOption {
      type = types.str;
      default = "gnome";
      description = ''
        Display-manager session to switch to when leaving Gaming Mode via
        "Switch to Desktop". Must match a session provided by the desktop
        profile (GNOME on Wayland is "gnome").
      '';
    };

    decky = mkEnableOption "Decky Loader (Steam Deck plugin loader)";

    amdGpu = mkEnableOption "AMD GPU specific tuning (Jovian)";
  };

  config = mkIf cfg.enable (mkMerge [
    {
      # Pull in the regular desktop (GNOME) as the "Switch to Desktop" target and
      # Steam with Proton-GE handling. mkDefault so a host can still override.
      shulker.system.profiles.desktop.enable = mkDefault true;
      shulker.system.modules.steam = {
        enable = mkDefault true;
        protonGE = mkDefault true;
      };

      jovian = {
        steam = {
          enable = true;
          autoStart = cfg.autoStart;
          user = cfg.user;
          desktopSession = cfg.desktopSession;
          # Make the HDR toggle appear in Steam > Settings > Display so gamescope
          # renders an HDR output. Sunshine then captures that HDR framebuffer
          # and streams it (HEVC Main10 / AV1) to HDR-capable Moonlight clients.
          # environment.STEAM_GAMESCOPE_HDR_SUPPORTED = "1";
          environment.__GL_VRR_ALLOWED = "1";
          environment.__GL_GSYNC_ALLOWED = "1";
          environment.STEAM_GAMESCOPE_VRR_SUPPORTED = "1";
        };
        decky-loader.enable = cfg.decky;
        hardware.has.amd.gpu = cfg.amdGpu;
      };

      # GameMode lets games request CPU/GPU performance tweaks on the fly.
      programs.gamemode.enable = true;

      # Jovian builds gamescope / the Steam session against its pinned nixpkgs and
      # publishes them to this Cachix; pull from it to avoid local rebuilds.
      nix.settings = {
        substituters = [ "https://jovian-nixos.cachix.org" ];
        trusted-public-keys = [
          "jovian-nixos.cachix.org-1:mAWLjAxLNlfxAnozUjOqGj4AxQwCl7MXwOfu7msVlAo="
        ];
      };
    }

    # Gaming Mode autostart: Jovian forces SDDM (Wayland) + autologin and boots
    # straight into the gamescope session. The desktop profile ships GDM and
    # disables autologin, so override those to avoid display-manager conflicts.
    # GNOME's "Switch to Desktop" target still works through SDDM.
    (mkIf cfg.autoStart {
      services.displayManager.gdm.enable = mkForce false;
      services.displayManager.autoLogin.enable = mkForce true;
    })
  ]);
}
