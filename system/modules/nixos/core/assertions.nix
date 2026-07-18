{ config, lib, ... }:

let
  modules = config.shulker.system.modules;
  impermanentServices = {
    "Beszel agent" = modules.beszel.agent.impermanence;
    "Beszel hub" = modules.beszel.hub.impermanence;
    Forgejo = modules.forgejo.impermanence;
    "Git Pages" = modules.git-pages.impermanence;
    "Home Assistant" = modules.home-assistant.impermanence;
    Newt = modules.newt.impermanence;
    Ollama = modules.ollama.impermanence;
    Pangolin = modules.pangolin.impermanence;
    "Pelican Panel" = modules.pelican.panel.impermanence;
    "Pelican Wings" = modules.pelican.wings.impermanence;
    Plex = modules.plex.impermanence;
    "Pocket ID" = modules.pocket-id.impermanence;
    Torrent = modules.torrent.impermanence;
  };
in
{
  assertions =
    lib.mapAttrsToList (name: enabled: {
      assertion = !enabled || modules.impermanence.enable;
      message = "${name} persistence requires shulker.system.modules.impermanence.enable.";
    }) impermanentServices
    ++ [
      {
        assertion = !modules.backup.enable || modules.backup.hetznerStorageBoxAccount != "";
        message = "Backups require a non-empty Hetzner Storage Box account.";
      }
      {
        assertion = !modules.backup.enable || modules.backup.dirs != [ ];
        message = "Backups are enabled but no source directories are configured.";
      }
      {
        assertion =
          !modules.nvidia.hybrid.enable
          || (
            modules.nvidia.hybrid.nvidiaBusId != ""
            && (modules.nvidia.hybrid.intelBusId != "" || modules.nvidia.hybrid.amdgpuBusId != "")
          );
        message = "Hybrid Nvidia graphics require the Nvidia bus ID and one integrated-GPU bus ID.";
      }
    ];
}
