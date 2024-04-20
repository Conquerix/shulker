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
    profiles.server.enable = true;
    modules = {
      user.home = ./home.nix;
      ssh_server.enable = true;
      docker.enable = true;
      searx = {
        enable = true;
        port = 23234;
        baseUrl = "shulker.fr";
      };
      wireguard.enable = true;
      wireguard.server = {
      	enable = true;
      	extInterface = "ens3";
      };
      uptime-kuma = {
      	enable = true;
      	port = 23231;
      	baseUrl = "the-inbetween.net";
      	subDomain = "status";
      };
    };
  };
}
