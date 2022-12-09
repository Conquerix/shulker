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
        privateKeyFile = "/etc/wireguard/private_key";
  
        peers = [
          # List of allowed peers.
          #{ # Warden
          #  publicKey = "{client public key}";
          #  allowedIPs = [ "192.168.10.2/32" ];
          #}
          { # Phantom
            publicKey = "twbugLyoNIV/U06EI0Gs29hd0QJKsHkpdoD3o/dE6zM=";
            allowedIPs = [ "10.100.0.3/32" ];
          }
          #{ # Allay
          #  publicKey = "{john doe's public key}";
          #  allowedIPs = [ "10.100.0.4/32" ];
          #}
        ];
      };
    };

    environment = mkIf (config.shulker.modules.impermanence.enable) {
      persistence."/nix/persist".files = [
        {file = "/etc/wireguard/private_key"; parentDirectory = { mode = "u=rw,g=,o="; };}
      ];
    };
  };
}
