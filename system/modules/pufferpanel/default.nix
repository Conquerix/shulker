{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.modules.pufferpanel;
in
{
  options.shulker.modules.pufferpanel = {
    enable = mkEnableOption "Enable pufferpanel";
    webPort = mkOption {
      description = "Port of pufferpanel webui";
      type = types.port;
      default = 8080;
    };
    sftpPort = mkOption {
      description = "Port of pufferpanel sftp server";
      type = types.port;
      default = 5657;
    };
    companyName = mkOption {
      description = "Name of pufferpanel company/org";
      type = types.str;
      default = "PufferPanel";
    };
    storagePath = mkOption {
      description = "Where to store pufferpanel's data, along with the minecraft servers";
      type = types.str;
      #default = "/var/lib/pufferpanel";
    };
  };

  config = mkIf cfg.enable {

#    services.nginx = {
#      enable = true;
#      streamConfig = ''
#        upstream pufferpanel-web {
#          server 127.0.0.1:24080;
#        }
#        
#        server {
#          listen {toString cfg.webPort};
#          proxy_pass pufferpanel-web;
#        }
#
#        upstream pufferpanel-sftp {
#          server 127.0.0.1:24057;
#        }
#        
#        server {
#          listen ${toString cfg.sftpPort};
#          proxy_pass pufferpanel-sftp;
#        }
#      '';
#    };

	virtualisation.oci-containers.containers = {
	  pufferpanel = {
	    image = "pufferpanel/pufferpanel:latest";
	    ports = [ "${toString cfg.webPort}:8080" "${toString cfg.sftpPort}:5657" "25565:25565" "25566:25566/udp" "25567:25567" "25568:25568/udp"];
        volumes = [
          "${cfg.storagePath}/config:/etc/pufferpanel"
          "${cfg.storagePath}/data:/var/lib/pufferpanel"
          "/var/run/docker.sock:/var/run/docker.sock"
        ];
	  };
	};
    
    #services.pufferpanel = {
    #  enable = true;
    #  extraPackages = with pkgs; [ bash curl gawk gnutar gzip ];
    #  package = pkgs.buildFHSEnv {
    #    name = "pufferpanel-fhs";
    #    runScript = lib.getExe pkgs.pufferpanel;
    #    targetPkgs = pkgs': with pkgs'; [ icu openssl zlib ];
    #  };
    #  environment = {
    #    PUFFER_WEB_HOST = ":${toString cfg.webPort}";
    #    PUFFER_DAEMON_SFTP_HOST = ":${toString cfg.sftpPort}";
    #    PUFFER_PANEL_SETTINGS_COMPANYNAME = "QSMP Fan Server";
    #    PUFFER_PANEL_REGISTRATIONENABLED = "false";
    #    PUFFER_LOGS = "${cfg.storagePath}/logs"
    #    PUFFER_DAEMON_DATA_CACHE = "${cfg.storagePath}/cache";
    #    PUFFER_DAEMON_DATA_SERVERS = "${cfg.storagePath}/data/servers";
    #    PUFFER_DAEMON_DATA_BINARIES = "${cfg.storagePath}/data/binaries";
    #  };
    #};
  };
}
