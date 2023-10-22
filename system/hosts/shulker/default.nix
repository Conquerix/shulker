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
          configuration = ''
            debug: false
            uuid: a49d2402-67bf-4e68-abd9-c4b44cb971b7
            token_id: 9ewWe0WPYyg8cQwj
            token: NkKHZ9Vc6zefYTmQaD0Pgmk695tnPqpVjj5D7rvdEB8x9typ4XC8x2RmpCH1qNS3
            api:
              host: 0.0.0.0
              port: 4443
              ssl:
                enabled: false
                cert: /etc/letsencrypt/live/shulker.the-inbetween.net/fullchain.pem
                key: /etc/letsencrypt/live/shulker.the-inbetween.net/privkey.pem
              upload_limit: 100
            system:
              data: /var/lib/pterodactyl/volumes
              sftp:
                bind_port: 2022
            allowed_mounts: []
            remote: 'https://admin.the-inbetween.net'
          '';
          pkg = (builtins.getFlake "github:TeamMatest/nix-wings/2de9ee5f2bf8b8d2eeb214ba272a1e7e2cbe7ae0").packages.x86_64-linux.default;
        };
      };
    };
  };
}
