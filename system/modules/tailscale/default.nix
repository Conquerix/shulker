{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.modules.tailscale;
in
{
  options.shulker.modules.tailscale = {
    enable = mkEnableOption "Enable tailscale client";
  };

  config = mkIf cfg.enable {
    services.tailscale = {
      enable = true;
      authKeyFile = config.opnix.secrets.tailscale-auth-key.path;
      extraUpFlags = [
        "--login-server" "https://vpn.shulker.link"
        "--advertise-exit-node"
      ];
      useRoutingFeatures = "both";
    };

    opnix.secrets.tailscale-auth-key = {
      source = "{{ op://Shulker/Headscale Preauth Key/key }}";
    };
  };

  opnix.systemdWantedBy = [ "tailscaled" "tailscaled-autoconnect" ];
}
