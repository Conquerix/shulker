{
  config,
  lib,
  ...
}:

with lib;
let
  cfg = config.shulker.system.modules.plex;
in
{
  options.shulker.system.modules.plex = {
    enable = mkEnableOption "Plex media server";

    impermanence = mkEnableOption "Persist Plex state across reboots (ephemeral root)";

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Open the ports Plex needs on the LAN (32400 etc).";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/plex";
      description = ''
        Where Plex keeps its database, metadata and cache. This grows large;
        point it at a persistent pool (e.g. /storage/...) on servers.
      '';
    };

    hardwareTranscoding = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Give the plex user access to /dev/dri so it can use GPU/QuickSync
        transcoding. Requires an active Plex Pass to actually be used.
      '';
    };

    extraGroups = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        Extra groups to add the plex user to, e.g. a shared media/torrent
        group so Plex can read downloads written by another service.
      '';
    };
  };

  config = mkIf cfg.enable {
    services.plex = {
      enable = true;
      openFirewall = cfg.openFirewall;
      dataDir = cfg.dataDir;
      user = "plex";
      group = "plex";
    };

    # Hardware (QuickSync / VAAPI / NVENC) transcoding needs render node access.
    users.users.plex.extraGroups =
      (optionals cfg.hardwareTranscoding [
        "render"
        "video"
      ])
      ++ cfg.extraGroups;

    environment.persistence = mkIf cfg.impermanence {
      "/nix/persist".directories = [
        {
          directory = cfg.dataDir;
          mode = "u=rwx,g=rx,o=";
          user = "plex";
          group = "plex";
        }
      ];
    };
  };
}
