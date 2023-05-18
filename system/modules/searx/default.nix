{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.modules.searx;
in
{
  options.shulker.modules.searx = {
    enable = mkEnableOption "Enable searx service";
    url = mkOption {
      type = types.str;
      default = "searx.example.com";
      description = "Default url where searx will be accessible.";
    };
    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Default internal port to open searx.";
    };
    address = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Default address to which searx will listen.";
    };
    secret_key = mkOption {
      type = types.str;
      default = "YOUNEEDTOMODIFYTHIS!!";
      description = "Default searx secret key.";
    };
  };

  config = mkIf cfg.enable {

    services.searx = {
      enable = true;
      package = pkgs.searxng;
      settings = {
        general.instance_name = "Shulker search";
        server.base_url = "https://${cfg.url}/";
        server.port = cfg.port;
        server.bind_address = "127.0.0.1";
        server.secret_key = cfg.secret_key;
    	};
    };

    #virtualisation.oci-containers.containers = {
    #  searxng = {
    #    image = "searxng/searxng:latest";
    #    ports = [ "${toString cfg.port}:8080" ];
    #    #cap_drop = [ "ALL" ];
    #    #cap_add = [ "CHOWN" "SETGID" "SETUID" ];
    #    environment = {
    #      INSTANCE_NAME = "Shulker search";
    #      SEARXNG_BASE_URL = "https://${cfg.url}/";
    #    };
    #  };
    #};

    
    services.nginx = {
      enable = true;
      virtualHosts."searx" = {
        serverName = cfg.url;
        forceSSL = true;
        enableACME = true;
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString cfg.port}";
        };
      };
    };
  };
}
