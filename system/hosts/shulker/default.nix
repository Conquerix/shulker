{ ... }:

{
  imports = [ ./hardware.nix ];

  networking.firewall.allowedTCPPorts = [ 80 443 23231 23241 ];

  security.acme.acceptTerms = true;

  services.nginx = {
    enable = true;
    streamConfig = ''
      upstream warden-VH2 {
        server 192.168.10.2:23241;
      }
      
      server {
        listen 23241;
        proxy_pass warden-VH2;
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
