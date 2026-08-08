{ pkgs, ... }:

{
  imports = [ ./hardware.nix ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernel.sysctl."vm.max_map_count" = 2147483642;

  # For zfs.
  networking.hostId = "2118dc3b";

  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver
      (intel-vaapi-driver.override { enableHybridCodec = true; })
      libva-vdpau-driver
      libvdpau-va-gl
      intel-compute-runtime # OpenCL filter support (hardware tonemapping and subtitle burn-in)
      vpl-gpu-rt # QSV on 11th gen or newer
    ];
  };

  shulker = {
    users.conquerix.enable = true;
    system = {
      profiles.server.enable = true;
      modules = {
        impermanence.enable = true;
        backup = {
          enable = true;
          hetznerStorageBoxAccount = "u515568-sub4";
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
        plex = {
          enable = true;
          impermanence = true;
          # Read finished downloads written by the torrent module.
          extraGroups = [ "torrent" ];
        };
        opencloud = {
          enable = true;
          stateDir = "/storage/flash/opencloud";
          dataset = "flash_pool/flash/storage/opencloud";
          bindAddress = "127.0.0.1";
          port = 23236;
          publicUrl = "https://cloud.shulker.link";
          oidcIssuer = "https://sso.shulker.link";
        };
        immich = {
          enable = true;
          stateDir = "/storage/flash/immich";
          dataset = "flash_pool/flash/storage/immich";
          datasetQuotaBytes = 1649267441664;
          bindAddress = "127.0.0.1";
          port = 23237;
          publicUrl = "https://photos.shulker.link";
          oidcIssuer = "https://sso.shulker.link";
          allowSetup = false;
          transcodingAcceleration = "qsv";
          preferredHardwareDevice = "/dev/dri/renderD128";
        };
        paperless = {
          enable = true;
          stateDir = "/storage/flash/paperless";
          dataset = "flash_pool/flash/storage/paperless";
          datasetQuotaBytes = 536870912000;
          bindAddress = "127.0.0.1";
          port = 23238;
          publicUrl = "https://documents.shulker.link";
          oidcIssuer = "https://sso.shulker.link";
        };
        torrent = {
          enable = true;
          downloadDir = "/storage/hdd/torrents";
          lanNetwork = "10.0.0.0/24";
          webUiPort = 23232;
        };
        webdav = {
          enable = true;
          dataDir = "/storage/flash/grapheneos-backups";
        };
      };
    };
  };

  services.wings.node = {
    uuid = "a01624a4-535b-4d83-8f2b-995388035a14";
    tokenId = "dwEserUfPiX164nw";
    remote = "https://panel.amphibian.network";
  };
}
