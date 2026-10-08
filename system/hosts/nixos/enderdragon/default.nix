{ config, lib, ... }:
{
  # Enderdragon is an impermanent server that runs Pelican workloads.
  imports = [ ./hardware.nix ];

  zramSwap.enable = true;

  # Changing the live D-Bus backend requires a separate planned reboot.
  services.dbus.implementation = "dbus";

  shulker = {
    users.conquerix.enable = true;
    system = {
      profiles.server.enable = true;
      modules = {
        impermanence.enable = true;
        openhands.worker = {
          enable = true;
          secretReference = "op://Shulker/OpenHands/Worker environment";
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

  # Session-key HTTP and first-frame WebSocket auth protect all coding operations.
  services.newt.blueprint.public-resources.openhands-worker =
    lib.mkIf config.shulker.system.modules.openhands.worker.enable
      {
        name = "OpenHands Agent Server";
        mode = "http";
        full-domain = "coding-api.shulker.link";
        ssl = true;
        auth.sso-enabled = false;
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
