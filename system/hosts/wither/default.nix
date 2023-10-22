{pkgs, lib, ... }:

{
  imports = [ ./hardware.nix ];


  boot.kernel.sysctl = { "vm.max_map_count" = 1048576; };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  programs.gamemode.enable = true;

  services.xserver.displayManager.gdm.wayland = lib.mkForce false;

  environment.systemPackages = with pkgs; [
    spot
  ];

  shulker = {
    modules = {
      _1password = {
        enable = true;
        users = [ "conquerix" ];
      };
      gnome = {
        enable = true;
      };
      steam = {
        enable = true;
        protonGE = true;
      };
      user.home = ./home.nix;
      impermanence = {
        enable = true;
        home = true;
        docker = true;
      };
      yubikey.enable = true;
      wireguard.client = {
        enable = true;
        clientIP = "192.168.10.4";
      };
      docker.enable = true;
      nvidia  = {
        enable = true;
      };
    };
    profiles = {
      desktop = {
        enable = true;
      };
    };
  };
}
