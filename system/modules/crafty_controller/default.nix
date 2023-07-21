{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.modules.crafty_controller;
in
{
  options.shulker.modules.crafty_controller = {
    enable = mkEnableOption "Enable crafty-controller";
    webPort = mkOption {
      description = "Port of crafty webui";
      type = types.port;
      default = 8080;
    };
    httpsPort = mkOption {
      description = "Port of crafty webui with https";
      type = types.port;
      default = 8443;
    };
    storagePath = mkOption {
      description = "Where to store crafty's data, along with the minecraft servers";
      type = types.str;
      default = "/var/lib/crafty-controller";
    };
  };
  
  config = mkIf cfg.enable {
    ## SQMP Pufferpanel and minecraft servers redirection
    services.nginx = {
      enable = true;
      virtualHosts."Admin-Panel-Minecraft" = {
        serverName = "crafty.shulker.fr";
        forceSSL = true;
        enableACME = true;
        locations."/" = {
          extraConfig = ''
            #This is important for websockets
            proxy_http_version 1.1;
            proxy_redirect off;
    
            # These are important for websockets.
            # They are required for crafty to function properly.
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection $http_connection;
            proxy_set_header X-Forwarded-Proto https;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header Host $host;
            #End important websocket parts
    
            proxy_pass https://localhost:${toString cfg.httpsPort};
    
            proxy_buffering off;
            client_max_body_size 0;
            proxy_connect_timeout  3600s;
            proxy_read_timeout  3600s;
            proxy_send_timeout  3600s;
            send_timeout  3600s;
          '';
        };
      };
    };
    

	virtualisation.oci-containers.containers = {
	  crafty-controller = {
	    image = "arcadiatechnology/crafty-4:latest";
	    ports = [ 
	      "${toString cfg.webPort}:8080"
	      "${toString cfg.httpsPort}:8443"
		  "25600-25999:25600-25999"
	      "25600-25999:25600-25999/udp"
	    ];
        volumes = [
          "${cfg.storagePath}/backups:/crafty/backups"
          "${cfg.storagePath}/logs:/crafty/logs"
          "${cfg.storagePath}/servers:/crafty/servers"
          "${cfg.storagePath}/config:/crafty/app/config"
          "${cfg.storagePath}/import:/crafty/import"
        ];
	  };
	};

	environment = mkIf (config.shulker.modules.impermanence.enable) {
	  persistence."/nix/persist".directories = [ "/var/lib/crafty-controller" ];
	};
  };
}
