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

    environment.systemPackages = with pkgs; [
      inputs.opnix.packages."${pkgs.system}".default
    ];

    systemd.services.opnix-secrets = {
      requires = [ "network-online.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
    };

    # sshd-keygen generates any *missing* configured host key — including the
    # opnix-provisioned one below. Unordered, it races opnix-secrets at boot
    # (both write the same path) and whoever wins determines the presented
    # host key: that was the rotating-host-key bug. Run keygen strictly after
    # opnix so it is a pure fallback for when 1Password is unreachable on a
    # host whose key was never provisioned (fresh install).
    systemd.services.sshd-keygen = {
      after = [ "opnix-secrets.service" ];
      wants = [ "opnix-secrets.service" ];
    };
    services.onepassword-secrets = {
      enable = true;
      tokenFile = "/etc/opnix-token";
      secrets = {
        sshed25519HostKey = {
          reference = "op://Shulker/${config.networking.hostName} ssh ed25519/private_key";
          mode = "0600";
          services = [ "sshd" ];
        };
      };
    };
  };
}
