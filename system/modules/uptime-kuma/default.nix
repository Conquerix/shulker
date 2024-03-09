{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.modules.uptime-kuma;
in
{
  options.shulker.modules.uptime-kuma = {
    enable = mkEnableOption "Enable uptime-kuma service.";
    url = mkOption {
      type = types.str;
      default = "status.example.com";
      description = "Url where uptime-kuma will be accessible.";
    };
    port = mkOption {
      type = types.port;
      default = 3001;
      description = "Internal port to open uptime-kuma.";
    };
    address = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Address to which uptime-kuma will listen.";
    };
    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/uptime-kuma/";
      description = "Directory to store uptime-kuma's data.";
    };
  };

  config = mkIf cfg.enable {

    services.uptime-kuma = {
      enable = cfg.enable;
      settings = {
      	HOST = cfg.address;
      	PORT = "${toString cfg.port}";
      	DATA_DIR = cfg.dataDir;
      };
    };
    
    services.nginx = {
      enable = true;
      virtualHosts = {
        "uptime-kuma" = {
	      serverName = cfg.url;
	      forceSSL = true;
	      enableACME = true;
	      locations."/" = {
	        proxyPass = "http://${cfg.address}:${toString cfg.port}";
	        extraConfig = ''
	          proxy_set_header Upgrade $http_upgrade;    
	          proxy_set_header Connection "upgrade";
	        '';
	      };
	    };
	  };
    };

    environment.persistence = mkIf (config.shulker.modules.impermanence.enable) {
      "/nix/persist".directories = [ cfg.dataDir ];
    };
  };
}
