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
      defaults.email = "${config.networking.hostName}@shulker.link";
      acceptTerms = true;
      certs."shulker.fr" = {
        domain = "shulker.fr";
        extraDomainNames = [ "*.shulker.fr" ];
        dnsProvider = "ovh";
        dnsPropagationCheck = true;
        webroot = null;
        credentialsFile = config.opnix.secrets.ovh-wildcard-ca.path;
      };
      certs."shulker.link" = {
        domain = "shulker.link";
        extraDomainNames = [ "*.shulker.link" ];
        dnsProvider = "ovh";
        dnsPropagationCheck = true;
        webroot = null;
        credentialsFile = config.opnix.secrets.ovh-wildcard-ca.path;
      };
      certs."the-inbetween.net" = {
        domain = "the-inbetween.net";
        extraDomainNames = [ "*.the-inbetween.net" ];
        dnsProvider = "ovh";
        dnsPropagationCheck = true;
        webroot = null;
        credentialsFile = config.opnix.secrets.ovh-wildcard-ca.path;
      };
    };

    networking.firewall = {
      enable = true;
      allowedTCPPorts = [ 80 443 ];
    };

    services.nginx = {
      enable = true;
      recommendedGzipSettings = true;
      recommendedOptimisation = true;
      recommendedTlsSettings = true;
      recommendedProxySettings = true;
    };

    users.users.nginx = {
      isSystemUser = true;
      group = "nginx";
      extraGroups = [ "acme" ];
    };

    users.groups.nginx = {};

    opnix.secrets.ovh-wildcard-ca = {
      source = "{{ op://Shulker/OVH wildcard certificate/OVH-wildcard-ca }}";
      mode = "0600";
    };

    opnix.systemdWantedBy = [
      "acme-fixperms"
      "acme-lockfiles"
      "acme-selfsigned-ca"
      "acme-shulker.fr"
      "acme-the-inbetween.net"
      "acme-selfsigned-shulker.fr"
      "acme-selfsigned-the-inbetween.net"
    ];
  };
}
