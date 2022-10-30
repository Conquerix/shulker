{ ... }:

{
  imports = [ ./hardware.nix ];

  shulker = {
    modules = {
      user.home = ./home.nix;
      ssh_server.enable = true;
      
    };
    profiles = {
      desktop = {
        enable = true;
        laptop = true;
    };
  };
}
