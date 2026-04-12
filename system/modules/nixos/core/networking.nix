{
  lib,
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
      settings.Resolve.Domains = [ "~." ];
    };

    # Disable this to try and solve the network manager wait online failed after each rebuild.
    #systemd.network.wait-online.enable = false;
    #boot.initrd.systemd.network.wait-online.enable = false;
  };
}
