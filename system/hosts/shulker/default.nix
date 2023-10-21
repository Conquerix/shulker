{ ... }:

{
  imports = [ 
    ./hardware.nix 
    #./minecraft.nix
  ];

  shulker = {
    modules = {
      user.home = ./home.nix;
      ssh_server.enable = true;
      #soft-serve.enable = true;
      docker.enable = true;
      searx = {
        enable = true;
        port = 23234;
        url = "searx.shulker.fr";
        };
      wireguard.server = {
      	enable = true;
      	extInterface = "ens3";
      };
    };
  };
}
