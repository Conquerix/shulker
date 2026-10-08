{ ... }:
{
  # Enderdragon is an impermanent server that runs Pelican workloads.
  imports = [ ./hardware.nix ];

  zramSwap.enable = true;

  # Preserve the running D-Bus backend; changing it requires a planned reboot.
  services.dbus.implementation = "dbus";

  shulker = {
    users.conquerix.enable = true;
    system = {
      profiles.server.enable = true;
      modules = {
        impermanence.enable = true;
        openhands = {
          enable = true;
          impermanence = true;
        };
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
            openFirewall = true;
            port = 23231;
          };
        };
      };
    };
  };

  services.newt.blueprint.public-resources.openhands-canvas = {
    name = "OpenHands";
    mode = "http";
    full-domain = "code.shulker.link";
    ssl = true;
    auth = {
      sso-enabled = true;
      sso-users = [ "conquerix@shulker.link" ];
      sso-roles = [ ];
      whitelist-users = [ ];
    };
    targets = [
      {
        hostname = "127.0.0.1";
        port = 23249;
        method = "http";
      }
    ];
  };

  services.wings.node = {
    uuid = "96308644-40c2-4277-96bb-3bd69754240a";
    tokenId = "vtnTRZIpulDH2VJ3";
    remote = "https://panel.amphibian.network";
  };

  boot.loader.grub.enable = true;
  boot.loader.grub.efiSupport = true;
  boot.loader.grub.device = "nodev";
  # Install the fallback EFI path so boot does not depend on firmware entries.
  boot.loader.grub.efiInstallAsRemovable = true;

  # boot.loader.grub.mirroredBoots = [
  #   {
  #     devices = [ "/dev/disk/by-uuid/5D35-7F32" ];
  #     path = "/boot-fallback";
  #   }
  # ];
  boot.supportedFilesystems = [ "zfs" ];
  # ZFS uses a stable host ID to guard pool ownership across machines.
  networking.hostId = "78986dce";
}
