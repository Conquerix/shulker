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
    };
  };

  config = mkIf cfg.enable {

	virtualisation.oci-containers.containers = {
	  crafty-controller = {
	    image = "arcadiatechnology/crafty-4:latest";
	    ports = [ 
	      "${toString cfg.webPort}:8080"
	      "${toString cfg.httpsPort}:8443"
		  "25600-25799:25600-25799"
	      "25800-25999:25800-25999/udp"
	    ];
        volumes = [
          "${cfg.storagePath}/backups:/crafty/backups"
          "${cfg.storagePath}/logs:/crafty/logs"
          "${cfg.storagePath}/servers:/crafty/servers"
          "${cfg.storagePath}/config:/crafty/config"
          "${cfg.storagePath}/import:/crafty/import"
        ];
	  };
	};
  };
}
