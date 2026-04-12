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
