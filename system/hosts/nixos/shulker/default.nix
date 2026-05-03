{ ... }:
{
  imports = [ ./hardware.nix ];

  zramSwap.enable = true;

  shulker = {
    users.conquerix.enable = true;
    system = {
      profiles.server.enable = true;
      modules = {
        impermanence.enable = true;
        backup = {
          enable = true;
          hetznerStorageBoxAccount = "u515568-sub2";
        };
        pangolin = {
          enable = true;
          impermanence = true;
        };
        newt = {
          enable = true;
          endpoint = "https://proxy.shulker.link";
        };
        pocket-id = {
          enable = true;
          impermanence = true;
          appUrl = "https://sso.shulker.link";
          port = 23231;
        };
        beszel.hub = {
          enable = true;
          impermanence = true;
          appUrl = "https://monitor.shulker.link";
          port = 23232;
        };
        forgejo = {
          enable = true;
          impermanence = true;
          baseUrl = "amphibian.network";
          subDomain = "git";
          httpPort = 23233;
        };
        beszel.agent = {
          enable = true;
          impermanence = true;
          hubEndpoint = "https://monitor.shulker.link";
          extraFilesystems = "/nix__Nix Store,/nix/persist__Persistent Partition";
        };
        pelican = {
          panel = {
            enable = true;
            impermanence = true;
            appUrl = "https://panel.amphibian.network";
            port = 23236;
          };
          wings = {
            enable = true;
            impermanence = true;
            port = 23237;
          };
        };
        nextcloud = {
          enable = true;
          impermanence = true;
          mainPort = 23238;
          aioPort = 23239;
        };
        git-pages = {
          enable = true;
          impermanence = true;
          repos = [
            {
              name = "amphibian-website";
              url = "https://git.amphibian.network/Amphibian/website.git";
              branch = "main";
              port = 23240;
            }
          ];
        };
      };
    };
  };

  services.wings.node = {
    uuid = "fb07692f-4f13-47f5-b2e3-8a99b71141d6";
    tokenId = "uHRV3hDpTejdX7Q0";
    remote = "https://panel.amphibian.network";
  };

  boot.loader.grub.enable = true;
  boot.loader.grub.efiSupport = true;
  boot.loader.grub.device = "nodev";
  boot.loader.grub.efiInstallAsRemovable = true;

  #boot.loader.grub.mirroredBoots = [
  #  { devices = [ "/dev/disk/by-uuid/5D35-7F32" ];
  #    path = "/boot-fallback"; }
  #];
  boot.supportedFilesystems = [ "zfs" ];
  networking.hostId = "6dc72d90";

  boot = {
    #kernelParams = [ "ip=144.76.176.22::144.76.176.31:255.255.255.224::enp6s0:none" ]; # Use if dhcp not available.
    initrd = {
      kernelModules = [ "igb" ]; # Check module with "lspci -v" -> driver in use for the ethernet adapter.
      network = {
        enable = true;
        ssh = {
          enable = true;
          port = 2222;
          hostKeys = [ "/nix/persist/etc/secrets/initrd/ssh_host_ed25519_key" ];
          authorizedKeys = [
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOcuA0ZxQyqfHlWrbdVT9Hu7/IQwZuh4aQa6X1gIHOSV"
          ];
        };
      };
      systemd.services.initrd-zfs-profile = {
        description = "Write ZFS load-key profile for initrd SSH shell";
        wantedBy = [ "initrd.target" ];
        serviceConfig = {
          Type = "oneshot";
        };
        script = ''
          cat <<'EOF' > /root/.profile
          if pgrep -x "zfs" > /dev/null
          then
            zfs load-key -a
            killall zfs
          else
            echo "zfs not running -- maybe the pool is taking some time to load for some unforseen reason."
          fi
          EOF
        '';
      };
    };
  };
}
