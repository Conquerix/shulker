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

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      5900
      5901
    ];
    allowedUDPPorts = [
      5900
      5901
    ];
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
    hashedPassword = "$y$j9T$I6gdt1KVyHZynHQ9.DiG20$7F3YxKP49wlkjxKukcUBNb23RzDq3VAgjsZS/wNrZI/";
    extraGroups = [
      "networkmanager"
      "cups"
      "audio"
      "video"
    ];
  };

  shulker = {
    system = {
      profiles.desktop = {
        enable = true;
        laptop = true;
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
    users.conquerix.enable = true;
  };
}
