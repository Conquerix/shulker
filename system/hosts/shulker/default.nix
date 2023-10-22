{ ... }:

{
  imports = [ 
    ./hardware.nix 
    #./minecraft.nix
  ];

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 80 443 2022 25565 4443 ];
  };

  services.nginx = {
    enable = true;
    virtualHosts."shulker-wings-node" = {
      serverName = "shulker.the-inbetween.net";
      forceSSL = true;
      enableACME = true;
      locations."/".extraConfig = ''
        proxy_set_header   X-Forwarded-For $remote_addr;
        proxy_set_header   Host $host;
        proxy_set_header Upgrade websocket;
        proxy_set_header Connection Upgrade;
        proxy_pass         "http://127.0.0.1:4443";
      '';
    };
    virtualHosts."warden-wings-node" = {
      serverName = "warden.the-inbetween.net";
      forceSSL = true;
      enableACME = true;
      locations."/".extraConfig = ''
        proxy_set_header   X-Forwarded-For $remote_addr;
        proxy_set_header   Host $host;
        proxy_set_header Upgrade websocket;
        proxy_set_header Connection Upgrade;
        proxy_pass         "http://192.168.10.2:4443";
      '';
    };
    virtualHosts."vindicator-wings-node" = {
      serverName = "vindicator.the-inbetween.net";
      forceSSL = true;
      enableACME = true;
      locations."/".extraConfig = ''
        proxy_set_header   X-Forwarded-For $remote_addr;
        proxy_set_header   Host $host;
        proxy_set_header Upgrade websocket;
        proxy_set_header Connection Upgrade;
        proxy_pass         "http://192.168.10.6:4443";
      '';
    };
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
      wireguard.server = {
      	enable = true;
      	extInterface = "ens3";
      };
      pterodactyl = {
        panel.enable = true;
        wings = {
          enable = true;
          pkg = (builtins.getFlake "github:TeamMatest/nix-wings/2de9ee5f2bf8b8d2eeb214ba272a1e7e2cbe7ae0").packages.x86_64-linux.default;
        };
      };
    };
  };
}
