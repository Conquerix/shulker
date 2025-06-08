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
              PublicKey = "+umM4HrYSjxV5AwN3bx/hJoOIQE/DvIV8hx2R8A4vmg=";
              AllowedIPs = ["10.100.0.2/32"];
            }
            { # Ender
              PublicKey = "egXy+mxcBdsaDwTmWYmdFNtb7TTmXftdqVAFgE5IcVg=";
              AllowedIPs = ["10.100.0.3/32"];
            }
          ];
        };
      };
      networks.wg-shulker = {
        matchConfig.Name = "wg-shulker";
        address = ["10.100.0.1/24"];
        networkConfig = {
          IPMasquerade = "ipv4";
          IPv4Forwarding = true;
        };
      };
    };
  

    opnix.secrets.wireguard-private-key = {
      source = "{{ op://Shulker/${config.networking.hostName}/Wireguard Private Key }}";
      mode = "0600";
      user = "systemd-networkd";
    };
  };
}