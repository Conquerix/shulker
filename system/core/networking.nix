{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
with lib;
{
  config = {
    networking.networkmanager = {
      enable = lib.mkDefault true;
      dns = "systemd-resolved";
    };

    networking.nameservers = [
      "9.9.9.9"
      "149.112.112.112"
    ];

    services.resolved = {
      enable = true;
      domains = [ "~." ];
      extraConfig = ''
        DNSStubListener=no
      '';
      #dnssec = "true";
      #dnsovertls = "true";
    };

    #Fix dns lookups at boot time when wireguard is enabled
    networking.dhcpcd.denyInterfaces = [
      "wg*"
      "tailscale*"
    ];

    # Disable this to try and solve the network manager wait online failed after each rebuild.
    systemd.network.wait-online.enable = false;
    boot.initrd.systemd.network.wait-online.enable = false;
  };
}
