{ config, inputs, lib, pkgs, ... }:

with lib;
{
  config = {
    boot = {
      loader.grub = {
        enable = true;
        efiSupport = true;
        device = "nodev";
      };

      # Enable running aarch64 binaries using qemu.
      binfmt.emulatedSystems = [ "aarch64-linux" ];

      # Clean temporary directory on boot.
      cleanTmpDir = true;

      # Enable support for nfs and ntfs.
      supportedFilesystems = [ "cifs" "ntfs" "nfs" ];
    };

    networking.networkmanager.enable = true;

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

    # List of bare minimal requirements for a system to have to bootstrap from
    environment.systemPackages = with pkgs; [
      curl
      git
      pciutils
      micro
    ];
  };
}
