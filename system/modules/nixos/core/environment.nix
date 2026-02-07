{
  config,
  lib,
  pkgs,
  ...
}:

let
  zfsCompatibleKernelPackages = lib.filterAttrs (
    name: kernelPackages:
    (builtins.match "linux_[0-9]+_[0-9]+" name) != null
    && (builtins.tryEval kernelPackages).success
    && (!kernelPackages.${config.boot.zfs.package.kernelModuleAttribute}.meta.broken)
  ) pkgs.linuxKernel.packages;
  latestKernelPackage = lib.last (
    lib.sort (a: b: (lib.versionOlder a.kernel.version b.kernel.version)) (
      builtins.attrValues zfsCompatibleKernelPackages
    )
  );
in

with lib;
{
  config = {
    system.stateVersion = "22.05";
    shulker.global.type = "nixos";
    boot = {
      kernelPackages = latestKernelPackage;

      # Enable running aarch64 binaries using qemu.
      binfmt.emulatedSystems = [ "aarch64-linux" ];

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

    virtualisation.oci-containers.backend = "docker";
    virtualisation.docker = {
      enable = true;
      enableOnBoot = true;
      autoPrune.enable = true;
    };

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
      docker-compose
      lazydocker
    ];

    programs.zsh.enable = true;
    programs.starship.enable = true;
  };
}
