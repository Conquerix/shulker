{ config, inputs, lib, pkgs, ... }:

with lib;
{
  config = {
    boot = {
      kernelPackages = pkgs.linuxPackages_latest;
      
      # Enable running aarch64 binaries using qemu.
      binfmt.emulatedSystems = [ "aarch64-linux" ];

      # Clean temporary directory on boot.
      cleanTmpDir = true;

      # Enable support for nfs and ntfs.
      supportedFilesystems = [ "cifs" "ntfs" "nfs" ];
    };

    hardware.enableRedistributableFirmware = true;

    networking.networkmanager.enable = true;

    users.groups.config.name = "config";

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
    };

    security.acme = {
      defaults.email = "pierre@fournier.net";
      acceptTerms = true;
    };

    # List of bare minimal requirements for a system to have to bootstrap from
    environment.systemPackages = with pkgs; [
      curl
      git
      pciutils
      micro
    ];
  };
}
