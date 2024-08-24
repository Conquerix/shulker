{pkgs, ... }:

{
  imports = [ ./hardware.nix ];

  boot.loader = {
  efi = {
    canTouchEfiVariables = true;
    efiSysMountPoint = "/boot";
    };
  grub = {
    enable = true;
    devices = ["nodev"];
    efiSupport = true;
    };
  };

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 5900 5901 ];
    allowedUDPPorts = [ 5900 5901 ];
  };

  services.gnome.gnome-remote-desktop.enable = true;

  environment.systemPackages = with pkgs; [
    spotify
    spotify-tray
    thunderbird
    libreoffice
    hunspell
    hunspellDicts.en_US
    hunspellDicts.fr-any
    gnome.gnome-remote-desktop
  ];

  users.extraUsers.camelia = {
    isNormalUser = true;
    hashedPassword = "$y$j9T$I6gdt1KVyHZynHQ9.DiG20$7F3YxKP49wlkjxKukcUBNb23RzDq3VAgjsZS/wNrZI/";
    extraGroups = [ "networkmanager" "cups" "audio" "video" ];
  };

  shulker = {
    modules = {
      _1password = {
        enable = true;
        users = [ "conquerix" ];
      };
      gnome.enable = true;
      ssh_server.enable = true;
      user.home = ./home.nix;
      impermanence = {
        enable = true;
        home = true;
      };
      yubikey.enable = true;
      wireguard.enable = true;
    };
    profiles = {
      desktop = {
        enable = true;
        laptop = true;
      };
    };
  };
}
