{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.modules.wiki-js;
in
{
  options.shulker.modules.wiki-js = {
    enable = mkEnableOption "Enable wiki-js service.";
    url = mkOption {
      type = types.str;
      default = "wiki.example.com";
      description = "Url where wiki-js will be accessible.";
    };
    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Default internal port to open wiki-js.";
    };
    address = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Default address to which wiki-js will listen.";
    };
  };

  config = mkIf cfg.enable {

    services.wiki-js = {
      enable = cfg.enable;
      settings.port = cfg.port;
    };
    
    services.nginx = {
      enable = true;
      virtualHosts."wiki-js" = {
        serverName = cfg.url;
        forceSSL = true;
        enableACME = true;
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString cfg.port}";
        };
      };
    };

    environment.persistence = mkIf (config.shulker.modules.impermanence.enable) {
      "/nix/persist".directories = [ "/var/lib/wiki-js" ];
    };
  };
}
