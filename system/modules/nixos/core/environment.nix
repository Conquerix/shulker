{
  config,
  lib,
  pkgs,
  ...
}:

with lib;
{
  config = {
    system.stateVersion = "22.05";
    shulker.global.type = "nixos";
    boot = {
      # Refuse to import a ZFS root pool that appears active on another host.
      # This is the safer default from NixOS 26.11 onward.
      zfs.forceImportRoot = false;

      # Clean temporary directory on boot.
      tmp.cleanOnBoot = true;

      # Enable support for nfs and ntfs.
      supportedFilesystems = [
        "cifs"
        "ntfs"
        "nfs"
      ];
    };

    hardware.enableRedistributableFirmware = true;

    systemd.settings.Manager.DefaultLimitNOFILE = "4096";

    console.keyMap = "fr";
    i18n.defaultLocale = "en_US.UTF-8";

    services = {
      cron.enable = true;
      locate.enable = true;
      timesyncd.enable = true;
      openssh = {
        enable = true;
        openFirewall = true;
        settings = {
          PasswordAuthentication = false;
          KbdInteractiveAuthentication = false;
        };
        hostKeys = [
          {
            type = "ed25519";
            path = config.services.onepassword-secrets.secrets.sshed25519HostKey.path;
          }
        ];
      };
    };

    # List of bare minimal requirements for a system to have to bootstrap from
    environment.systemPackages = with pkgs; [
      pciutils
      xclip
    ];

    programs.zsh.enable = true;
    programs.starship.enable = true;
  };
}
