{ ... }:

{
  imports = [ ./hardware.nix ];

  services.nginx.enable = true;

  security.acme.acceptTerms = true;

  networking.firewall.allowedTCPPorts = [ 80 443 ];

  shulker = {
    modules = {
      user.home = ./home.nix;
      ssh_server = {
        enable = true;
        tor = {
          enable = true;
          port = 45022;
        };
      };
    };
  };
}
