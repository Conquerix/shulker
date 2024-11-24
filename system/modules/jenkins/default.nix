{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.modules.jenkins;
in
{
  options.shulker.modules.jenkins = {
    enable = mkEnableOption "Enable jenkins service";
    baseUrl = mkOption {
      type = types.str;
      default = "example.com";
      description = "Default url where jenkins will be accessible.";
    };
    subDomain = mkOption {
      type = types.str;
      default = "jenkins";
      description = "Default subdomain where jenkins will be accessible.";
    };
    httpPort = mkOption {
      type = types.port;
      default = 8080;
      description = "Default internal port to open jenkins.";
    };
    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/jenkins";
      description = "State Directory.";
    };
  };

  config = mkIf cfg.enable {

    services.jenkins = {
      enable = true;
      package = pkgs.jenkins-latest;
      port = cfg.httpPort;
      plugins = import ./plugins.nix { inherit (pkgs) fetchurl stdenv; };
      listenAddress = "127.0.0.1";
      home = cfg.stateDir;
    };

    services.nginx = {
      enable = true;
      virtualHosts."jenkins" = {
        serverName = "${cfg.subDomain}.${cfg.baseUrl}";
        forceSSL = true;
        useACMEHost = cfg.baseUrl;
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString cfg.httpPort}";
        };
      };
    };
  };
}
