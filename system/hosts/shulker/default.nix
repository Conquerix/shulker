{ ... }:

{
  imports = [ 
    ./hardware.nix 
    ./minecraft.nix
  ];

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 80 443 ];
  };

  shulker = {
    modules = {
      user.home = ./home.nix;
      ssh_server.enable = true;
      soft-serve.enable = true;
      docker.enable = true;
      wireguard.server = {
      	enable = true;
      	extInterface = "ens3";
      };
    };
  };
}
