{ config, inputs, lib, pkgs, ... }:

let
  isUnstable = config.boot.zfs.package == pkgs.zfsUnstable;
  zfsCompatibleKernelPackages = lib.filterAttrs (
    name: kernelPackages:
    (builtins.match "linux_[0-9]+_[0-9]+" name) != null
    && (builtins.tryEval kernelPackages).success
    && (
      (!isUnstable && !kernelPackages.zfs.meta.broken)
      || (isUnstable && !kernelPackages.zfs_unstable.meta.broken)
    )
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
    boot = {
      kernelPackages = latestKernelPackage;
      
      # Enable running aarch64 binaries using qemu.
      binfmt.emulatedSystems = [ "aarch64-linux" ];

      # Clean temporary directory on boot.
      tmp.cleanOnBoot = true;

      # Enable support for nfs and ntfs.
      supportedFilesystems = [ "cifs" "ntfs" "nfs" ];
    };

    hardware.enableRedistributableFirmware = true;

    networking.networkmanager = {
      enable = lib.mkDefault true;
      dns = "none";
    };
    networking.nameservers = [ "9.9.9.9" ];

    # Disable this to try and solve the nework manager wait online failed after each rebuild.
    systemd.network.wait-online.enable = false;
    boot.initrd.systemd.network.wait-online.enable = false;

    systemd.extraConfig = "DefaultLimitNOFILE=4096";

    programs.ssh.extraConfig = "IdentityFile /secrets/ssh-ed25519-key";

    nix = {
      settings = {

        # Save space by hardlinking store directories containing the exact same content.
        auto-optimise-store = true;

        allowed-users = [ "root" ];
      };

      gc = {
        automatic = true;
        dates = "weekly";
        options = "--delete-older-than 30d";
      };
    };

    time.timeZone = "Europe/Paris";
    i18n.defaultLocale = "fr_FR.UTF-8";

    services = {
      cron.enable = true;
      locate.enable = true;
      timesyncd.enable = true;
    };

    # List of bare minimal requirements for a system to have to bootstrap from
    environment.systemPackages = with pkgs; [
      curl
      git
      git-lfs
      pciutils
      micro
      xclip
      openssl
      wl-clipboard
      zip
      bat
      htop
      nh
      devenv
      devbox # portable dev environments
      gping # better ping
      eza # better ls
    ];

    environment.shellAliases = {
      ping = "gping";
      l = "eza -oluag --git";
      ls = "eza";
      ll = "eza -olug --git";
    };

    programs = {
      direnv.enable = true;
      starship.enable = true;
    };

    opsm = {
      enable = true;
      refreshInterval = null;
      secretDir = "/secrets";
    };

    opsm.secrets.ssh-ed25519-key = {
      secretRef = "op://Shulker/${config.networking.hostName} ssh ed25519/private_key";
      sshKey = true;
      mode = "0600";
    };

    environment.persistence."/nix/persist" = mkIf (config.shulker.modules.impermanence.enable) {
      files = [
        {file = config.opsm.serviceAccountTokenPath; parentDirectory = { mode = "u=rw,g=,o="; };}
      ];
    };
  };
}
