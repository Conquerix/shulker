{ lib, pkgs, config, ... }:

{
  networking.nat.enable = true;
  networking.nat.externalInterface = "enp5s0";
  networking.nat.internalInterfaces = [ "wireguard-s2s" ];
  networking.firewall.allowedUDPPorts = [ 51820 ];
  boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
  networking.wireguard.interfaces = {
    wireguard-s2s = {
      # Determines the IP address and subnet of the server's end of the tunnel interface.
      ips = [ "10.100.0.1/8" ];

      # The port that WireGuard listens to. Must be accessible by the client.
      listenPort = 51820;

      # This allows the wireguard server to route your traffic to the internet and hence be like a VPN
      
      # For this to work you have to set the dnsserver IP of your router (or dnsserver of choice) in your clients
      #postSetup = ''
      #  ${pkgs.iptables}/bin/iptables -t nat -A POSTROUTING -s 10.0.0.0/8 -o enp5s0 -j MASQUERADE
      #'';

      # This undoes the above command
      #postShutdown = ''
      #  ${pkgs.iptables}/bin/iptables -t nat -D POSTROUTING -s 10.0.0.0/8 -o enp5s0 -j MASQUERADE
      #'';

      # Path to the private key file.
      privateKeyFile = config.opnix.secrets.wireguard-private-key.path;

      peers = [
        # List of allowed peers.
        { # Nether
          publicKey = "+umM4HrYSjxV5AwN3bx/hJoOIQE/DvIV8hx2R8A4vmg=";
          allowedIPs = [ "10.100.0.2/32" "10.0.0.0/16" ];
        }
        { # Ender
          publicKey = "egXy+mxcBdsaDwTmWYmdFNtb7TTmXftdqVAFgE5IcVg=";
          allowedIPs = [ "10.100.0.3/32"  "10.10.0.0/16" ];
        }
      ];
    };
  };

  opnix.secrets.wireguard-private-key = {
    source = "{{ op://Shulker/${config.networking.hostName}/Wireguard Private Key }}";
  };
}