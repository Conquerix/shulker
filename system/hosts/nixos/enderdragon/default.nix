{ ... }:
{
  imports = [ ./hardware.nix ];

  zramSwap.enable = true;

  shulker = {
    system = {
      profiles.server.enable = true;
      modules = {
        impermanence.enable = true;
        backup = {
          enable = true;
          hetznerStorageBoxAccount = "u515568-sub3";
        };
        newt = {
          enable = true;
          endpoint = "https://proxy.shulker.link";
        };
        beszel.agent = {
          enable = true;
          impermanence = true;
          hubEndpoint = "https://monitor.shulker.link";
          extraFilesystems = "/nix__Nix Store,/nix/persist__Persistent Partition";
        };
        pelican = {
          wings = {
            enable = true;
            impermanence = true;
            port = 23231;
          };
        };
      };
    };
    users.conquerix.enable = true;
  };

  services.wings.node = {
    uuid = "96308644-40c2-4277-96bb-3bd69754240a";
    tokenId = "vtnTRZIpulDH2VJ3";
    remote = "https://panel.amphibian.network";
  };

  boot.loader.grub.enable = true;
  boot.loader.grub.efiSupport = true;
  boot.loader.grub.device = "nodev";
  boot.loader.grub.efiInstallAsRemovable = true;

  # boot.loader.grub.mirroredBoots = [
  #   {
  #     devices = [ "/dev/disk/by-uuid/5D35-7F32" ];
  #     path = "/boot-fallback";
  #   }
  # ];
  boot.supportedFilesystems = [ "zfs" ];
  networking.hostId = "78986dce";
}
