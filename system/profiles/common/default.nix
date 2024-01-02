{ config, inputs, lib, pkgs, ... }:

with lib;
{
  config = {
    boot = {
      kernelPackages = config.boot.zfs.package.latestCompatibleLinuxPackages;
      
      # Enable running aarch64 binaries using qemu.
      binfmt.emulatedSystems = [ "aarch64-linux" ];

      # Clean temporary directory on boot.
      tmp.cleanOnBoot = true;

      # Enable support for nfs and ntfs.
      supportedFilesystems = [ "cifs" "ntfs" "nfs" ];
    };

    hardware.enableRedistributableFirmware = true;

    networking.networkmanager.enable = lib.mkDefault true;

    nix = {
      settings = {

        # Save space by hardlinking store directories containing the exact same content.
        auto-optimise-store = true;

        allowed-users = [ "root" ];
      };

      gc = {
        automatic = true;
        dates = "weekly";
        options = "--delete-older-than 30d";
      };
    };

    time.timeZone = "Europe/Paris";
    i18n.defaultLocale = "fr_FR.UTF-8";

    services = {
      cron.enable = true;
      locate.enable = true;
      timesyncd.enable = true;
    };

    security.acme = {
      defaults.email = "pierre@fournier.net";
      acceptTerms = true;
    };

    services.nginx = {
      recommendedGzipSettings = true;
      recommendedOptimisation = true;
      recommendedTlsSettings = true;
      recommendedProxySettings = true;
    };

    # List of bare minimal requirements for a system to have to bootstrap from
    environment.systemPackages = with pkgs; [
      curl
      git
      git-lfs
      pciutils
      micro
      xclip
      openssl
      wl-clipboard
      zip
      bat
    ];

    environment.persistence."/nix/persist" = mkIf (config.shulker.modules.impermanence.enable) {
      files = [
        {file = opsm.serviceAccountTokenPath; parentDirectory = { mode = "u=rw,g=,o="; };}
      ];
    };

    opsm = {
      enable = true;
      refreshInterval = null;
    };
  };
}
