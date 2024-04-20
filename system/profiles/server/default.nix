{ config, inputs, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.profiles.server;
in
{
  options.shulker.profiles.server = {
    enable = mkEnableOption "server profile";
  };

  config = mkIf cfg.enable {
    security.acme = {
      defaults.email = "pierre@fournier.net";
      acceptTerms = true;
      certs."shulker.fr" = {
        domain = "shulker.fr";
        extraDomainNames = [ "*.shulker.fr" ];
        dnsProvider = "ovh";
        dnsPropagationCheck = true;
        credentialsFile = "/secrets/ovh-shulker-wildcard-ca";
      };
    };

    services.nginx = {
      recommendedGzipSettings = true;
      recommendedOptimisation = true;
      recommendedTlsSettings = true;
      recommendedProxySettings = true;
    };

    opsm.secrets.ovh-shulker-wildcard-ca = {
      secretRef = "op://Shulker/OVH wildcard certificate shulker.fr/OVH-shulker-wildcard-ca";
      mode = "0600";
    };
  };
}
