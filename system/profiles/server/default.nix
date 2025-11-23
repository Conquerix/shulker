{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:

with lib;
let
  cfg = config.shulker.system.profiles.server;
in
{
  options.shulker.system.profiles.server = {
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
        credentialsFile = config.services.onepassword-secrets.secrets.ovhWildcardCa.path;
      };
      certs."shulker.link" = {
        domain = "shulker.link";
        extraDomainNames = [ "*.shulker.link" ];
        dnsProvider = "ovh";
        dnsPropagationCheck = true;
        webroot = null;
        credentialsFile = config.services.onepassword-secrets.secrets.ovhWildcardCa.path;
      };
      certs."the-inbetween.net" = {
        domain = "the-inbetween.net";
        extraDomainNames = [ "*.the-inbetween.net" ];
        dnsProvider = "ovh";
        dnsPropagationCheck = true;
        webroot = null;
        credentialsFile = config.services.onepassword-secrets.secrets.ovhWildcardCa.path;
      };
      certs."amphibian.network" = {
        domain = "amphibian.network";
        extraDomainNames = [ "*.amphibian.network" ];
        dnsProvider = "ovh";
        dnsPropagationCheck = true;
        webroot = null;
        credentialsFile = config.services.onepassword-secrets.secrets.ovhWildcardCa.path;
      };
    };

    networking.firewall = {
      enable = true;
      allowedTCPPorts = [
        80
        443
      ];
    };

    networking = {
      dhcpcd.enable = false;
      networkmanager.enable = false;
      useNetworkd = true;
    };
    systemd.network.enable = true;

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

    users.groups.nginx = { };

    services.onepassword-secrets.secrets.ovhWildcardCa = {
      reference = "op://Shulker/OVH wildcard certificate/OVH-wildcard-ca";
      mode = "0600";
      services = [
        "acme-fixperms"
        "acme-lockfiles"
        "acme-selfsigned-ca"
        "acme-shulker.fr"
        "acme-beyond.smp"
        "acme-shulker.link"
        "acme-the-inbetween.net"
        "acme-selfsigned-shulker.fr"
        "acme-selfsigned-beyond.smp"
        "acme-selfsigned-shulker.link"
        "acme-selfsigned-the-inbetween.net"
      ];
    };
  };
}
