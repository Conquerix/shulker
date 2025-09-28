{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
with lib;
{
  config = {

    security.sudo.enable = false;
    security.sudo-rs = {
      enable = true;
      wheelNeedsPassword = false;
      execWheelOnly = true;
    };

    programs._1password.enable = true;

    opnix = {
      environmentFile = "/etc/opnix.env";
      systemdWantedBy = [
        "docker"
        "sshd"
      ]; # "tailscaled" "tailscaled-autoconnect"
      secrets = {
        #tailscale-auth-key.source = "{{ op://Shulker/Headscale Preauth Key/key }}";
        ssh-ed25519-host-key = {
          source = "{{ op://Shulker/${config.networking.hostName} ssh ed25519/private_key }}";
          mode = "0600";
        };
      };
    };
  };
}
