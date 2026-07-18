{ pkgs, ... }:

{
  imports = [ ./hardware.nix ];

  boot.loader = {
    efi = {
      canTouchEfiVariables = true;
      efiSysMountPoint = "/boot";
    };
    grub = {
      enable = true;
      devices = [ "nodev" ];
      efiSupport = true;
    };
  };

  environment.systemPackages = with pkgs; [
    fastmail-desktop
    spotify
    spotify-tray
    thunderbird
    libreoffice
    hunspell
    hunspellDicts.en_US
    hunspellDicts.fr-any
  ];

  users.extraUsers.camelia = {
    isNormalUser = true;
    hashedPasswordFile = "/etc/secrets/camelia-password-hash";
    extraGroups = [
      "networkmanager"
      "cups"
      "audio"
      "video"
    ];
  };

  shulker = {
    users.conquerix.enable = true;
    system = {
      profiles.desktop = {
        enable = true;
        laptop = true;
        remoteDesktop = true;
      };
      modules = {
        impermanence = {
          enable = true;
          home = true;
        };
        steam.enable = true;
        yubikey.enable = true;
      };
    };
  };
}
