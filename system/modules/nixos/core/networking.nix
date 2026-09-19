{
  lib,
  ...
}:
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

    systemd.network.wait-online.enable = lib.mkForce true;
    boot.initrd.systemd.network.wait-online.enable = lib.mkForce true;
  };
}
