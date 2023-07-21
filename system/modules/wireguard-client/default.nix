{ config, lib, pkgs, ... }:

with lib;
let cfg = config.shulker.modules.wireguard.client;
in
{
  options.shulker.modules.wireguard.client = {
    enable = mkEnableOption "Enable wireguard client";
    clientIP = mkOption {
    	description = ''Address of the client in the server's subnet'';
    	type = types.str;
    	default = "192.160.10.0";
    };
    vpn = mkEnableOption "Enable vpn mode";
  };

  config = mkIf cfg.enable {
    networking.firewall = {
      allowedUDPPorts = [ 51820 ];
    };
  
    networking.wireguard.interfaces = {
      # "wg0" is the network interface name. You can name the interface arbitrarily.
      wg0 = {
        # Determines the IP address and subnet of the server's end of the tunnel interface.
        ips = [ "${cfg.clientIP}/24" ];
  
        # The port that WireGuard listens to. Must be accessible by the client.
        listenPort = 51820;

        # Path to the private key file.
        privateKeyFile = "/etc/wireguard/private_key";
  
        peers = [
          { # Shulker server
            publicKey = "2xrdv1hBlJAQx8jo5P6hie6QzWSjbdGC8wP4pvCP6Rs=";
            allowedIPs = if cfg.vpn then [ "0.0.0.0/0" ] else [ "192.168.10.0/24" ];
            endpoint = "141.94.96.139:51820";
            persistentKeepalive = 25;
          }
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
