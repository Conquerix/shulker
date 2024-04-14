{ ... }:

{
  imports = [ 
    ./hardware.nix 
  ];

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 80 443 ];
  };

  shulker = {
    modules = {
      user.home = ./home.nix;
      ssh_server.enable = true;
      docker.enable = true;
      searx = {
        enable = true;
        port = 23234;
        url = "searx.shulker.fr";
      };
      wireguard.enable = true;
      wireguard.server = {
      	enable = true;
      	extInterface = "ens3";
      };
      uptime-kuma = {
      	enable = true;
      	port = 23231;
      	url = "status.the-inbetween.net";
      };
    };
  };
}
