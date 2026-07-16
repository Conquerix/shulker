{
  config,
  lib,
  ...
}:

with lib;
let
  cfg = config.shulker.system.modules.impermanence;
in
{
  options.shulker.system.modules.impermanence = {
    enable = mkEnableOption "Ephemeral root (& home) support";
    home = mkEnableOption "Link /home to /nix/persist/home";
  };

  config = mkIf cfg.enable {

    environment.persistence."/nix/persist" = {

      hideMounts = true;

      directories = [
        "/var/log"
        "/var/lib/nixos"
        "/var/lib/bluetooth"
        "/var/lib/systemd/coredump"
        "/var/lib/acme"
        # opnix-provisioned secrets (incl. the sshd host key) and its change
        # detection state. Without this, every boot wipes the host key,
        # sshd-keygen regenerates a random one at the same path, and the SSH
        # host key rotates whenever opnix can't reach 1Password before sshd
        # starts (DNS races network-online at boot).
        "/var/lib/opnix"
        "/etc/NetworkManager/system-connections"
        "/etc/nixos"
        "/etc/secrets"
        "/root/.ssh"
        "/var/lib/docker"
        (mkIf cfg.home "/home")
      ];

      files = [
        "/etc/machine-id"
        {
          file = config.services.onepassword-secrets.tokenFile;
          parentDirectory.mode = "u=rw,g=,o=";
        }
      ];
    };
  };
}
