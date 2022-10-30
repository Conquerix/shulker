{ ... }:

{
  imports = [ ./hardware.nix ];

  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
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
