{ config, lib, pkgs, ... }:

with lib;
let cfg = config.shulker.modules.wirenix;
in
{
  options.shulker.modules.wirenix = {
      enable = mkEnableOption "Enable wirenix meshing";
      extInterface = mkOption {
        description = ''Hardware interface for the NAT'';
        type = types.str;
        default = "eth0";
      };
    };

  config = mkIf cfg.enable {

    wirenix = {
      enable = true;
      configurer = "static"; # defaults to "static", could also be "networkd"
      keyProviders = ["acl"]; # could also be ["agenix-rekey"] or ["acl" "agenix-rekey"]
      aclConfig = import ./acl.nix;
    };
    
    opsm.secrets.wireguard-private-key.secretRef = "op://Shulker/${config.networking.hostName}/Wireguard Private Key";
  };
}
