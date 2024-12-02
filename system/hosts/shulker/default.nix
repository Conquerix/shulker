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
      wireguard.enable = true;
      uptime-kuma = {
        enable = true;
        port = 23231;
        baseUrl = "the-inbetween.net";
        subDomain = "status";
      };
      searx = {
        enable = true;
        port = 23234;
        baseUrl = "shulker.fr";
      };
      authentik = {
        enable = true;
        baseUrl = "shulker.fr";
        subDomain = "auth";
      };
      netbird.server = {
        enable = true;
        baseUrl = "shulker.fr";
        subDomain = "vpn";
        mgmtPort = 23235;
        signalPort = 23236;
        clientID = "tNb6JtW0UOEBHJ3SYpYPZEoVYEets45YYQP2qQSE";
        authBaseUrl = "https://auth.shulker.fr/application/o";
        oidcConfigEndpoint = "https://auth.shulker.fr/application/o/netbird/.well-known/openid-configuration";
      };
    };
  };
}
