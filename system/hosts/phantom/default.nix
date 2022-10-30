{ ... }:

{
  imports = [ ./hardware.nix ];

  boot = {
    loader.grub = {
      enable = true;
      efiSupport = true;
      device = "/dev/disk/by-uuid/8764-2ADD";
    };
  };

  shulker = {
    modules = {
      user.home = ./home.nix;
      ssh_server.enable = true;
      impermanence = {
        enable = true;
        home = true;
      };
    };
    profiles = {
      desktop = {
        enable = true;
        laptop = true;
      };
    };
  };
}
