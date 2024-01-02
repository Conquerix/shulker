{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.modules.outline;
in
{
  options.shulker.modules.outline = {
    enable = mkEnableOption "Enable outline service.";
    url = mkOption {
      type = types.str;
      default = "wiki.example.com";
      description = "Url where outline will be accessible.";
    };
    port = mkOption {
      type = types.port;
      default = 3000;
      description = "Default internal port to open outline.";
    };
    minio = {
      port = mkOption {
        type = types.port;
        default = 9000;
        description = "Default internal for minio storage.";
      };
      consolePort = mkOption {
        type = types.port;
        default = 9001;
        description = "Default internal for minio storage.";
      };
      region = mkOption {
        type = types.str;
        default = "shulker";
        description = "Region of the minio server. Can be whatever you want";
      };
      url = mkOption {
        type = types.str;
        default = "minio.example.com";
        description = "Url where minio admin console will be accessible.";
      };
      accessKey = mkOption {
        type = types.str;
        default = "changeme";
        description = "S3 Access Key, to be found in minio config.";
      };
    };
    address = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Default address to which outline will listen.";
    };
  };

  config = mkIf cfg.enable {

  	services.minio = {
  	  enable = true;
  	  consoleAddress = ":${toString cfg.minio.consolePort}";
  	  listenAddress = ":${toString cfg.minio.port}";
  	  region = cfg.minio.region;
  	  rootCredentialsFile = "/etc/minio/secrets/minio-root-credentials";
  	};

    services.outline = {
      enable = cfg.enable;
      publicUrl = "https://${cfg.url}";
      port = cfg.port;
      storage = {
        #storageType = "local"; #set this when not using minio.
        secretKeyFile = "/var/lib/outline/s3_secret_file";
        uploadBucketUrl = "https://${cfg.minio.url}";
        uploadBucketName = "outline";
        region = cfg.minio.region;
        accessKey = cfg.minio.accessKey;
      };
      forceHttps = false;
      oidcAuthentication = {
        authUrl = "https://${config.shulker.modules.keycloak.url}/realms/master/protocol/openid-connect/auth";
        tokenUrl = "https://${config.shulker.modules.keycloak.url}/realms/master/protocol/openid-connect/token";
        userinfoUrl = "https://${config.shulker.modules.keycloak.url}/realms/master/protocol/openid-connect/userinfo";
        clientId = "outline";
        clientSecretFile = "/var/lib/outline/client_secret_file";
        scopes = [ "openid" "email" "profile" ];
        usernameClaim = "preferred_username";
        displayName = "Keycloak";
      };
    };
    
    services.nginx = {
      enable = true;
      virtualHosts = {
        "outline" = {
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
	    "minio" = {
	      serverName = cfg.minio.url;
	      forceSSL = true;
	      enableACME = true;
	      locations."/" = {
	        proxyPass = "http://${cfg.address}:${toString cfg.minio.port}";
	      };
	    };
	    "minio-console" = {
	      serverName = "admin.${cfg.minio.url}";
	      forceSSL = true;
	      enableACME = true;
	      locations."/" = {
	        proxyPass = "http://${cfg.address}:${toString cfg.minio.consolePort}";
	      };
	    };
	  };
    };

    environment.persistence = mkIf (config.shulker.modules.impermanence.enable) {
      "/nix/persist".directories = [ "/var/lib/outline" "/var/lib/minio" "/etc/minio/secrets" ];
    };
  };
}
