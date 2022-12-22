{ ... }:

{
  imports = [ ./hardware.nix ];

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 80 443 23231 25501 ];
    allowedUDPPorts = [ 25501 ];
  };

  security.acme.acceptTerms = true;

  services.nginx = {
    enable = true;
    streamConfig = ''
      upstream warden-minecraft-VH2 {
        server 192.168.10.2:25501;
      }
      
      server {
        listen 25501;
        proxy_pass warden-minecraft-VH2;
      }
    '';
  };

  shulker = {
    modules = {
      user.home = ./home.nix;
      ssh_server.enable = true;
      soft-serve.enable = true;
      wireguard.server = {
      	enable = true;
      	extInterface = "ens3";
      };
    };
  };
}
