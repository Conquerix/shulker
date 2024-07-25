{ config, lib, pkgs, ... }:

with lib;
let cfg = config.shulker.modules.encrypted_dns;
in
{
  options.shulker.modules.encrypted_dns = {
    enable = mkEnableOption "Enable encrypted dns setup";
    dns_list = mkOption {
      description = ''Address of the client in the server's subnet'';
      type = types.listOf types.str;
      default = [
        "sdns://AQMAAAAAAAAADDkuOS45Ljk6ODQ0MyBnyEe4yHWM0SAkVUO-dWdG3zTfHYTAC4xHA2jfgh2GPhkyLmRuc2NyeXB0LWNlcnQucXVhZDkubmV0"
        "sdns://AQMAAAAAAAAAEjE0OS4xMTIuMTEyLjk6ODQ0MyBnyEe4yHWM0SAkVUO-dWdG3zTfHYTAC4xHA2jfgh2GPhkyLmRuc2NyeXB0LWNlcnQucXVhZDkubmV0"
        "sdns://AQMAAAAAAAAAFDE0OS4xMTIuMTEyLjExMjo4NDQzIGfIR7jIdYzRICRVQ751Z0bfNN8dhMALjEcDaN-CHYY-GTIuZG5zY3J5cHQtY2VydC5xdWFkOS5uZXQ"
      ];
    };
  };

  config = mkIf cfg.enable {
    networking.networkmanager.dns = "none";
    networking.nameservers = [ "127.0.0.1" "::1" ];

    services.dnscrypt-proxy2 = {
      enable = true;
      settings = {
        ipv6_servers = true;
        require_dnssec = true;
        sources.public-resolvers = {
          urls = [
            "https://raw.githubusercontent.com/DNSCrypt/dnscrypt-resolvers/master/v3/public-resolvers.md"
            "https://download.dnscrypt.info/resolvers-list/v3/public-resolvers.md"
          ];
          cache_file = "/var/lib/dnscrypt-proxy2/public-resolvers.md";
          minisign_key = "RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3";
        };
        server_names = cfg.dns_list;
      };
    };

    systemd.services.dnscrypt-proxy2.serviceConfig = {
      StateDirectory = "dnscrypt-proxy";
    };

    environment = mkIf (config.shulker.modules.impermanence.enable) {
      persistence."/nix/persist".files = [
        {file = "/var/lib/dnscrypt-proxy2/public-resolvers.md"; parentDirectory = { mode = "u=rw,g=,o="; };}
      ];
    };
  };
}
