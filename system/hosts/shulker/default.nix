{ ... }:

{
  imports = [ 
    ./hardware.nix 
    #./minecraft.nix
  ];

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 80 443 2022 25565 4443 ];
    allowedUDPPorts = [ 25565 ];
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
    virtualHosts."leantime" = {
      serverName = "colab.the-inbetween.net";
      forceSSL = true;
      enableACME = true;
      locations."~* \.io".extraConfig = ''
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        client_max_body_size 50M;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Frame-Options SAMEORIGIN;
        proxy_buffers 256 16k;
        proxy_buffer_size 16k;
        client_body_timeout 60;
        send_timeout 300;
        lingering_timeout 5;
        proxy_connect_timeout 1d;
        proxy_send_timeout 1d;
        proxy_read_timeout 1d;
        proxy_pass http://127.0.0.1:23238;
      '';
      locations."/".extraConfig = ''
        client_max_body_size 50M;
        proxy_set_header Connection "";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Frame-Options SAMEORIGIN;
        proxy_buffers 256 16k;
        proxy_buffer_size 16k;
        proxy_read_timeout 600s;
        proxy_cache_revalidate on;
        proxy_cache_min_uses 2;
        proxy_cache_use_stale timeout;
        proxy_cache_lock on;
        proxy_http_version 1.1;
        proxy_pass http://127.0.0.1:23238;
      '';
    };
  };
  

  shulker = {
    modules = {
      user.home = ./home.nix;
      ssh_server.enable = true;
      docker.enable = true;
      wiki-js = {
      	#enable = true;
      	port = 23235;
      	url = "old.wiki.the-inbetween.net";
      };
      outline = {
      	enable = true;
      	port = 23236;
      	url = "wiki.the-inbetween.net";
      	minio = {
      	  port = 23240;
      	  consolePort = 23239;
      	  url = "minio.the-inbetween.net";
      	  accessKey = "v5iyXbS0w8FUeJAEc6sp";
      	};
      };
      searx = {
        enable = true;
        port = 23234;
        url = "searx.shulker.fr";
      };
      keycloak = {
      	enable = true;
      	port = 23237;
      	url = "auth.the-inbetween.net";
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
