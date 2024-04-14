{ config, lib, pkgs, ... }:

with lib;
let 
  cfg = config.shulker.modules.wireguard;
  wgPort = 51821;
  devices = [
    {
      name = "shulker";
      server = true;
      extInterface = "ens3";
      address = "10.10.10.1";
      publicKey = "vLo4XYe84WcCnkLynjO2SjBzHmFuYeuFN0CF5b/CfBc=";
      endpoint = {
        ip = "51.178.27.137";
        port = wgPort;
      };
    }
    {
      name = "warden";
      address = "10.10.10.2";
      publicKey = "gfwhPNVOMoBxaCXP+dIcuLv+r2aat127wE+vO20Y/l0=";
    }
    {
      name = "phantom";
      address = "10.10.10.3";
      publicKey = "f2m5/gMPILz9ISGiAtwZFEWcU01jzU899bJBuhTiuyc=";
    }
    {
      name = "wither";
      address = "10.10.10.4";
      publicKey = "9JNyydvMlIDGpOCwAW6a8TzPALGvRq2UKBiPFLV8GwM=";
    }
    {
      name = "guardian";
      address = "10.10.10.5";
      publicKey = "J2amctRH90iC1bnd2UnqOp9D9Rpbgmb0w/Xs+caB83U=";
    }
    {
      name = "vindicator";
      address = "10.10.10.6";
      publicKey = "2xrdv1hBlJAQx8jo5P6hie6QzWSjbdGC8wP4pvCP6Rs=";
      endpoint = {
        ip = "141.94.96.139";
        port = wgPort;
      };
    }
    {
      name = "enderdragon";
      address = "10.10.10.7";
      publicKey = "k40E/7Z1DpaiwkTPTnn660N7A/V9jwgwjsL2Lm0OSlU=";
      endpoint = {
        ip = "136.243.40.242";
        port = wgPort;
      };
    }
    {
      name = "endermite";
      address = "10.10.10.8";
      publicKey = "LoGAYxqvBJYxBOY39VRd9vmyVAy592NDxQb2iBOf5wU=";
    }
  ];

  hosts = listToAttrs (map (x: {name = x.name; value = x;}) devices);

  host = hosts.${config.networking.hostName};

in {

  options.shulker.modules.wireguard = {
    enable = mkEnableOption "Enable wireguard server";
  };

  config = mkIf cfg.enable {
    networking = {
      nat = mkIf (host ? server && host.server) {
        enable = true;
        externalInterface = host.extInterface;
        internalInterfaces = [ "wg-shulker" ];
      };
      # Map the hostnames for easy addressing, both as "hostname" and "hostname.wg"
      hosts = listToAttrs (map (x: {
        name = x.address;
        value = [ "${x.name}" "${x.name}.wg" ];
      }) devices);
      firewall = {
        allowedUDPPorts = [ wgPort ];
        # Trust all traffic on this interface
        trustedInterfaces = [ "wg-shulker" ];
      };
      wireguard.interfaces.wg-shulker = {
        privateKeyFile = "/secrets/wireguard-private-key";
        ips = [ "${host.address}/24" ];
        listenPort = wgPort;

        postSetup = mkIf (host ? server && host.server) ''
          ${pkgs.iptables}/bin/iptables -t nat -A POSTROUTING -s 10.10.10.0/24 -o ${host.extInterface} -j MASQUERADE
        '';
  
        # This undoes the above command
        postShutdown = mkIf (host ? server && host.server) ''
          ${pkgs.iptables}/bin/iptables -t nat -D POSTROUTING -s 10.10.10.0/24 -o ${host.extInterface} -j MASQUERADE
        '';

        # There is no problem with having a peer device listed for itself, it is ignored.
        # Endpoints are a hint as to were to find the device, but connections can be accepted from anywhere.

        # Maps the devices list to configured Wireguard peers.
        # It adds an endpoint if that device has a public endpoint, which
        # should be the case for all servers.
        peers = if (host ? server && host.server) 
          then
            (map (x: {
              inherit (x) publicKey;
              allowedIPs = [ "${x.address}/32" ];
              endpoint = mkIf (x ? endpoint) "${x.endpoint.ip}:${toString x.endpoint.port}";
            }) devices)
          else
            ([{
              publicKey = hosts.shulker.publicKey;
              allowedIPs = [ "10.10.10.0/24" ];
              endpoint = "${hosts.shulker.endpoint.ip}:${toString hosts.shulker.endpoint.port}";
              persistentKeepalive = 25;
            }]);
      };
    };

    opsm.secrets.wireguard-private-key.secretRef = "op://Shulker/${config.networking.hostName}/Wireguard Private Key";
  };
}
