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
        credentialsFile = "/secrets/ovh-wildcard-ca";
      };
      certs."the-inbetween.net" = {
        domain = "the-inbetween.net";
        extraDomainNames = [ "*.the-inbetween.net" ];
        dnsProvider = "ovh";
        dnsPropagationCheck = true;
        credentialsFile = "/secrets/ovh-wildcard-ca";
      };
      certs."fournier.ltd" = {
        domain = "fournier.ltd";
        extraDomainNames = [ "*.fournier.ltd" ];
        dnsProvider = "ovh";
        dnsPropagationCheck = true;
        credentialsFile = "/secrets/ovh-wildcard-ca";
      };
    };

    services.nginx = {
      recommendedGzipSettings = true;
      recommendedOptimisation = true;
      recommendedTlsSettings = true;
      recommendedProxySettings = true;
    };

    users.users.nginx.extraGroups = [ "acme" ];

    opsm.secrets.ovh-wildcard-ca = {
      secretRef = "op://Shulker/OVH wildcard certificate/OVH-wildcard-ca";
      mode = "0600";
    };
  };
}
