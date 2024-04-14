{ config, lib, pkgs, ... }:

with lib;
let 
  cfg = config.shulker.modules.wireguard;
  wgPort = 51821;
  wgHostInfo = {
    shulker = {
      address = "10.10.10.1";
      pubkey = "vLo4XYe84WcCnkLynjO2SjBzHmFuYeuFN0CF5b/CfBc=";
      endpoint = "51.178.27.137:${toString wgPort}";
    };
    warden = {
      address = "10.10.10.2";
      pubkey = "gfwhPNVOMoBxaCXP+dIcuLv+r2aat127wE+vO20Y/l0=";
    };
    phantom = {
      address = "10.10.10.3";
      pubkey = "f2m5/gMPILz9ISGiAtwZFEWcU01jzU899bJBuhTiuyc=";
    };
    wither = {
      address = "10.10.10.4";
      pubkey = "9JNyydvMlIDGpOCwAW6a8TzPALGvRq2UKBiPFLV8GwM=";
    };
    guardian = {
      address = "10.10.10.5";
      pubkey = "J2amctRH90iC1bnd2UnqOp9D9Rpbgmb0w/Xs+caB83U=";
    };
    vindicator = {
      address = "10.10.10.6";
      pubkey = "2xrdv1hBlJAQx8jo5P6hie6QzWSjbdGC8wP4pvCP6Rs=";
      endpoint = "141.94.96.139:${toString wgPort}";
    };
    enderdragon = {
      address = "10.10.10.7";
      pubkey = "k40E/7Z1DpaiwkTPTnn660N7A/V9jwgwjsL2Lm0OSlU=";
      endpoint = "136.243.40.242:${toString wgPort}";
    };
    endermite = {
      address = "10.10.10.8";
      pubkey = "LoGAYxqvBJYxBOY39VRd9vmyVAy592NDxQb2iBOf5wU=";
    };
  };

  host = wgHostInfo.${config.networking.hostName};
in
{
  options.shulker.modules.wireguard = {
    enable = mkEnableOption "Enable wireguard server";
  };

  config = mkIf cfg.enable {
    networking.firewall = {
      allowedTCPPorts = [ wgPort ];
      allowedUDPPorts = [ wgPort ];
      trustedInterfaces = ["wg-shulker"];
    };
  
    networking.wireguard.interfaces.wg-shulker = {
      ips = ["${host.address}/24"];
      privateKeyFile = "/secrets/wireguard-private-key";
    };

    services.wgautomesh = {
      enable = true;
      gossipSecretFile = "/secrets/wgautomesh-gossip-secret";
      enablePersistence = true;
      settings = {
        interface = "wg-shulker";
        peers = pkgs.lib.mapAttrsToList (_: value: value) (
          removeAttrs wgHostInfo [config.networking.hostName]
        );
      };
    };

    environment.persistence."/nix/persist" = mkIf (config.shulker.modules.impermanence.enable) {
      files = [
        {file = "/var/lib/wgautomesh/state"; parentDirectory = { mode = "u=rw,g=,o="; };}
      ];
    };

    opsm.secrets.wireguard-private-key.secretRef = "op://Shulker/${config.networking.hostName}/Wireguard Private Key";
    opsm.secrets.wgautomesh-gossip-secret.secretRef = "op://Shulker/wgautomesh/secret key";
  };
}
