{ ... }:

{
  imports = [ ./hardware.nix ];

  services.nginx.enable = true;

  security.acme.acceptTerms = true;

  networking.firewall.allowedTCPPorts = [ 80 443 23231 ];

  services.tor = {
    enable = true;
    client.enable = true;
    torsocks.enable = true;
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
