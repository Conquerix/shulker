{ ... }:
{
  # Silverfish is the impermanent Home Assistant server.
  imports = [ ./hardware.nix ];

  zramSwap.enable = true;

  shulker = {
    users.conquerix.enable = true;
    system = {
      profiles.server.enable = true;
      modules = {
        impermanence.enable = true;
        newt = {
          enable = true;
          endpoint = "https://proxy.shulker.link";
        };
        beszel.agent = {
          enable = true;
          impermanence = true;
          hubEndpoint = "https://monitor.shulker.link";
          extraFilesystems = "/nix";
        };
        home-assistant = {
          enable = true;
          impermanence = true;
          openFirewall = true;
        };
      };
    };
  };

  boot.loader.grub.enable = true;
  boot.loader.grub.efiSupport = true;
  boot.loader.grub.device = "nodev";
  # Install the fallback EFI path so boot does not depend on firmware entries.
  boot.loader.grub.efiInstallAsRemovable = true;

  networking.hostId = "6dc72d90";
}
