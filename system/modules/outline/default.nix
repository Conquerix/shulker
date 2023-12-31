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
      description = "Default internal port to open wiki-js.";
    };
    address = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Default address to which wiki-js will listen.";
    };
  };

  config = mkIf cfg.enable {

    services.outline = {
      enable = cfg.enable;
      publicUrl = "http://${cfg.address}:${toString cfg.port}";
      storage.storageType = "local";
    };
    
    services.nginx = {
      enable = true;
      virtualHosts."outline" = {
        serverName = cfg.url;
        forceSSL = true;
        enableACME = true;
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString cfg.port}";
        };
      };
    };

    environment.persistence = mkIf (config.shulker.modules.impermanence.enable) {
      "/nix/persist".directories = [ "/var/lib/outline" ];
    };
  };
}
