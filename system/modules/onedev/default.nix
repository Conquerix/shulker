{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.modules.onedev;
in
{
  options.shulker.modules.onedev = {
    enable = mkEnableOption "Enable onedev";
    webPort = mkOption {
      description = "Port of onedev webui";
      type = types.port;
      default = 6610;
    };
    nodePort = mkOption {
      description = "Port of onedev for node connection";
      type = types.port;
      default = 6611;
    };
    storagePath = mkOption {
      description = "Where to store crafty's data, along with the minecraft servers";
      type = types.str;
      default = "/var/lib/onedev";
    };
  };

  
  config = mkIf cfg.enable {
    ## SQMP Pufferpanel and minecraft servers redirection
    #services.nginx = {
    #  enable = true;
    #  virtualHosts."onedev" = {
    #    serverName = "crafty.shulker.fr";
    #    forceSSL = true;
    #    enableACME = true;
    #    locations."/" = {
    #      extraConfig = ''
    #        #This is important for websockets
    #        proxy_http_version 1.1;
    #        proxy_redirect off;
    #
    #        # These are important for websockets.
    #        # They are required for crafty to function properly.
    #        proxy_set_header Upgrade $http_upgrade;
    #        proxy_set_header Connection $http_connection;
    #        proxy_set_header X-Forwarded-Proto https;
    #        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    #        proxy_set_header Host $host;
    #        #End important websocket parts
    #
    #        proxy_pass https://localhost:${toString cfg.httpsPort};
    #
    #        proxy_buffering off;
    #        client_max_body_size 0;
    #        proxy_connect_timeout  3600s;
    #        proxy_read_timeout  3600s;
    #        proxy_send_timeout  3600s;
    #        send_timeout  3600s;
    #      '';
    #    };
    #  };
    #};

	virtualisation.oci-containers.containers = {
	  onedev = {
	    image = "1dev/server";
	    ports = [ 
	      "${toString cfg.webPort}:6610"
	      "${toString cfg.nodePort}:6611"
	    ];
        volumes = [
          "${cfg.storagePath}:/opt/onedev"
          "/run/docker.sock:/var/run/docker.sock"
        ];
	  };
	};

	environment = mkIf (config.shulker.modules.impermanence.enable) {
	  persistence."/storage/mass/persist".directories = [ "${cfg.storagePath}" ];
	};
  };
}
