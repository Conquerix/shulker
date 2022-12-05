{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.modules.headscale;
in
{
  options.shulker.modules.headscale = {
    enable = mkEnableOption "Enable headscale module";
    dns = mkOption {
      type = types.listOf types.str;
      default = [ "9.9.9.9" "149.112.112.112" ];
      description = "DNS to use";
    };
    magicDomain = mkOption {
      type = types.str;
      default = "";
      description = "Base domain to create the hostnames for MagicDNS";
      example = "mydomain.com";
    };
  };

  config = mkIf cfg.enable {
   services = {
    headscale = {
      enable = true;
      address = "0.0.0.0";
      dns = {
        baseDomain = cfg.magicDomain;
        nameservers = cfg.dns;
      };
      port = 8085;
      serverUrl = "https://headscale.shulker.fr";
      logLevel = "trace";
      settings = {
        logtail.enabled = false;
      };
    };

    nginx.virtualHosts = {
      "headscale.shulker.fr" = {
        forceSSL = true;
        enableACME = true;
        locations."/".proxyPass =
          "http://localhost:${toString config.services.headscale.port}";
      };
    };
  };

  environment.systemPackages = [ config.services.headscale.package ];

  security.acme.certs = {
    "headscale.shulker.fr".email = "pierre@fournier.net";
  };

  environment.persistence = mkIf config.shulker.modules.impermanence.enable {
    "/nix/persist".directories = [ "/var/lib/headscale" ];
    };
  };
}
