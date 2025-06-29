{ config, lib, pkgs, ... }:

with lib;
let cfg = config.shulker.modules.wireguard;
in
{
  options.shulker.modules.wireguard = {
      enable = mkEnableOption "Enable wireguard server for multi-site vpn";
      extInterface = mkOption {
        description = ''Hardware interface for the NAT'';
        type = types.str;
        default = "eth0";
      };
    };

  config = mkIf cfg.enable {
    # enable NAT
    networking.nat.enable = true;
    networking.nat.externalInterface = cfg.extInterface;
    networking.nat.internalInterfaces = [ "wg-shulker" ];
    networking.firewall = {
      allowedUDPPorts = [ 51920 ];
    };

    boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

    systemd.network = {
      enable = true;
      netdevs = {
        "50-wg-shulker" = {
          netdevConfig = {
            Kind = "wireguard";
            Name = "wg-shulker";
            MTUBytes = "1300";
          };
          wireguardConfig = {
            PrivateKeyFile = config.opnix.secrets.wireguard-private-key.path;
            ListenPort = 51920;
          };
          wireguardPeers = [
            { # Nether
              PublicKey = "62B950xZNC23mjb/UVWFfCELGGv2b+tIVbuuc09sGDI=";
              AllowedIPs = ["10.100.0.2/32" "10.0.0.0/16" "192.168.1.20/32"];
            }
            { # Ender
              PublicKey = "egXy+mxcBdsaDwTmWYmdFNtb7TTmXftdqVAFgE5IcVg=";
              AllowedIPs = ["10.100.0.3/32" "10.10.0.0/16"];
            }
          ];
        };
      };
      networks = {
        wg-shulker = {
          matchConfig.Name = "wg-shulker";
          address = ["10.100.0.1/8"];
          #gateway = ["10.100.0.2" "10.100.0.3"];
          networkConfig = {
            IPMasquerade = "ipv4";
            IPv4Forwarding = true;
          };
        };
      };
    };
  

    opnix.secrets.wireguard-private-key = {
      source = "{{ op://Shulker/${config.networking.hostName}/Wireguard Private Key }}";
      mode = "0600";
      user = "systemd-network";
    };
  };
}