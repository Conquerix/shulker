{ config, lib, pkgs, ... }:

with lib;
let cfg = config.shulker.modules.wireguard.server;
in
{
  options.shulker.modules.wireguard.server = {
      enable = mkEnableOption "Enable wireguard server";
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
    networking.nat.internalInterfaces = [ "wg0" ];
    networking.firewall = {
      allowedUDPPorts = [ 51820 ];
    };

    boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
  
    networking.wireguard.interfaces = {
      # "wg0" is the network interface name. You can name the interface arbitrarily.
      wg0 = {
        # Determines the IP address and subnet of the server's end of the tunnel interface.
        ips = [ "192.168.10.1/24" ];
  
        # The port that WireGuard listens to. Must be accessible by the client.
        listenPort = 51820;
  
        # This allows the wireguard server to route your traffic to the internet and hence be like a VPN
        
        # For this to work you have to set the dnsserver IP of your router (or dnsserver of choice) in your clients
        postSetup = ''
          ${pkgs.iptables}/bin/iptables -t nat -A POSTROUTING -s 192.168.10.0/24 -o ${cfg.extInterface} -j MASQUERADE
        '';
  
        # This undoes the above command
        postShutdown = ''
          ${pkgs.iptables}/bin/iptables -t nat -D POSTROUTING -s 192.168.10.0/24 -o ${cfg.extInterface} -j MASQUERADE
        '';
  
        # Path to the private key file.
        privateKeyFile = "/secrets/wireguard-private-key";
  
        peers = [
          # List of allowed peers.
          { # Warden
            publicKey = "gfwhPNVOMoBxaCXP+dIcuLv+r2aat127wE+vO20Y/l0=";
            allowedIPs = [ "192.168.10.2/32" ];
          }
          { # Phantom
            publicKey = "f2m5/gMPILz9ISGiAtwZFEWcU01jzU899bJBuhTiuyc=";
            allowedIPs = [ "192.168.10.3/32" ];
          }
          { # Wither
          	publicKey = "9JNyydvMlIDGpOCwAW6a8TzPALGvRq2UKBiPFLV8GwM=";
          	allowedIPs = [ "192.168.10.4/32" ];
          }
          { # Guardian
          	publicKey = "J2amctRH90iC1bnd2UnqOp9D9Rpbgmb0w/Xs+caB83U=";
          	allowedIPs = [ "192.168.10.5/32" ];
          }
          { # Vindicator
            publicKey = "2xrdv1hBlJAQx8jo5P6hie6QzWSjbdGC8wP4pvCP6Rs=";
            allowedIPs = [ "192.168.10.6/32" ];
          }
        ];
      };
    };

    opsm.secrets.wireguard-private-key.secretRef = "op://Shulker/${config.networking.hostName}/Wireguard Private Key";

    environment = mkIf (config.shulker.modules.impermanence.enable) {
      persistence."/nix/persist".files = [
        {file = "/run/secrets/wireguard-private-key"; parentDirectory = { mode = "u=rw,g=,o="; };}
      ];
    };
  };
}
