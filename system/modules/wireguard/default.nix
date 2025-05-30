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
  
    networking.wireguard.interfaces = {
      # "wg-shulker" is the network interface name. You can name the interface arbitrarily.
      wg-shulker = {
        # Determines the IP address and subnet of the server's end of the tunnel interface.
        ips = [ "10.100.0.1/24" ];
  
        # The port that WireGuard listens to. Must be accessible by the client.
        listenPort = 51920;
  
        # This allows the wireguard server to route your traffic to the internet and hence be like a VPN
        
        # For this to work you have to set the dnsserver IP of your router (or dnsserver of choice) in your clients
        postSetup = ''
          ${pkgs.iptables}/bin/iptables -t nat -A POSTROUTING -s 10.100.0.0/24 -o ${cfg.extInterface} -j MASQUERADE
        '';
  
        # This undoes the above command
        postShutdown = ''
          ${pkgs.iptables}/bin/iptables -t nat -D POSTROUTING -s 10.100.0.0/24 -o ${cfg.extInterface} -j MASQUERADE
        '';
  
        # Path to the private key file.
        privateKeyFile = config.opnix.secrets.ssh-ed25519-host-key.path;
  
        peers = [
          # List of allowed peers.
          { # Nether
            publicKey = "+umM4HrYSjxV5AwN3bx/hJoOIQE/DvIV8hx2R8A4vmg=";
            allowedIPs = [ "10.100.0.2/32" ];
          }
          { # Ender
            publicKey = "egXy+mxcBdsaDwTmWYmdFNtb7TTmXftdqVAFgE5IcVg=";
            allowedIPs = [ "10.100.0.3/32" ];
          }
        ];
      };
    };

    opnix.secrets.ssh-ed25519-host-key = {
      source = "{{ op://Shulker/${config.networking.hostName}/Wireguard Private Key }}";
      mode = "0600";
    };
  };
}