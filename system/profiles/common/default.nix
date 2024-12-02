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
      dns = "systemd-resolved";
    };

    networking.nameservers = [ "9.9.9.9" "149.112.112.112" ];

    services.resolved = {
      enable = true;
      dnssec = "true";
      domains = [ "~." ];
      fallbackDns = [ "1.1.1.1#one.one.one.one" "1.0.0.1#one.one.one.one" ];
      dnsovertls = "true";
      extraConfig = ''
        DNSStubListener=no
      '';
    };

    security.sudo.enable = false;
    security.sudo-rs = {
      enable = true;
      wheelNeedsPassword = false;
    };

    programs._1password.enable = true;
    virtualisation.oci-containers.backend = "docker";
    virtualisation.docker = {
      enable = true;
      enableOnBoot = true;
    };

    #Fix dns lookups at boot time when wireguard is enabled
    networking.dhcpcd.denyInterfaces = [ "wg*" "tailscale*" ];

    # Disable this to try and solve the network manager wait online failed after each rebuild.
    systemd.network.wait-online.enable = false;
    boot.initrd.systemd.network.wait-online.enable = false;

    systemd.extraConfig = "DefaultLimitNOFILE=4096";

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
      openssh = {
        enable = true;
        openFirewall = true;
        hostKeys = [ { type = "ed25519"; path = config.opnix.secrets.ssh-ed25519-host-key.path; } ];
      };
      tailscale = {
        enable = true;
        authKeyFile = config.opnix.secrets.tailscale-auth-key.path;
        extraUpFlags = [ "--login-server" "https://vpn.shulker.link" "--advertise-exit-node" ];
        useRoutingFeatures = "both";
      };
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
      docker-compose
      lazydocker
    ];

    environment.shellAliases = {
      ping = "gping";
      l = "eza -oluag --git";
      ls = "eza";
      ll = "eza -olug --git";
      ".." = "cd ..";
    };

    programs = {
      direnv.enable = true;
      starship.enable = true;
    };

    opnix = {
      environmentFile = "/etc/opnix.env";
      systemdWantedBy = [ "docker" "tailscaled" "tailscaled-autoconnect" "sshd" ];
      secrets = {
        tailscale-auth-key.source = "{{ op://Shulker/Headscale Preauth Key/key }}";
        ssh-ed25519-host-key = {
          source = "{{ op://Shulker/${config.networking.hostName} ssh ed25519/private_key }}";
          mode = "0600";
        };
      };
    };
  };
}
