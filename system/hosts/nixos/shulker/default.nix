{ config, lib, ... }:
{
  # Shulker hosts the fleet's ingress, identity, monitoring, and collaboration services.
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
        # Separate provider home and narrow coding broker keep production Hermes isolated.
        hermes-trial = {
          enable = true;
          impermanence = true;
          allowedUsers = [ 9 ];
          allowedChannels = [ 4 ];
          model = "gpt-6.1-sol";
          # Stable item identity avoids invalid URI characters in its display name.
          secretReference = "op://Shulker/tiszplnlwtnaxf5kuofd6mctwq/Environment";
        };
        openhands = {
          frontend.enable = true;
          broker = {
            enable = true;
            secretReference = "op://Shulker/OpenHands/Broker key";
          };
        };
        # Zulip stays on loopback; Newt provides HTTPS with native Zulip authentication.
        zulip = {
          enable = true;
          impermanence = true;
          administratorEmail = "pierre@fournier.live";
          oidcClientId = "e925593b-ff69-492f-83bd-7e9115e3748f";
          secretReference = "op://Shulker/Zulip Trial/Secrets";
          # Verified source address of requests through the loopback Docker port.
          trustedProxyAddresses = [
            "127.0.0.1"
            "172.21.0.1"
          ];
        };
        hermes-agent = {
          enable = true;
          impermanence = true;
          webUi = {
            enable = true;
            port = 23234;
            publicUrl = "https://hermes.shulker.link";
          };
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
            openFirewall = true;
            port = 23237;
          };
        };
        nextcloud = {
          enable = true;
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

  # Native Zulip login protects the API; a second proxy login breaks mobile clients.
  services.newt.blueprint.public-resources.zulip-trial =
    lib.mkIf config.shulker.system.modules.zulip.enable
      {
        name = "Zulip Trial";
        mode = "http";
        full-domain = "chat.shulker.link";
        ssl = true;
        auth.sso-enabled = false;
        targets = [
          {
            hostname = "127.0.0.1";
            port = config.shulker.system.modules.zulip.port;
            method = "http";
          }
        ];
      };

  # The owner signs in through Pangolin; the coding API uses native key auth.
  services.newt.blueprint.public-resources.openhands-canvas =
    lib.mkIf config.shulker.system.modules.openhands.frontend.enable
      {
        name = "OpenHands Canvas";
        mode = "http";
        full-domain = "code.shulker.link";
        ssl = true;
        auth = {
          sso-enabled = true;
          sso-users = [ "conquerix@shulker.link" ];
          sso-roles = [ ];
          whitelist-users = [ ];
        };
        targets = [
          {
            hostname = "127.0.0.1";
            port = 23250;
            method = "http";
          }
        ];
      };

  services.wings.node = {
    uuid = "fb07692f-4f13-47f5-b2e3-8a99b71141d6";
    tokenId = "uHRV3hDpTejdX7Q0";
    remote = "https://panel.amphibian.network";
  };

  boot.loader.grub.enable = true;
  boot.loader.grub.efiSupport = true;
  boot.loader.grub.device = "nodev";
  # Install the fallback EFI path so boot does not depend on firmware entries.
  boot.loader.grub.efiInstallAsRemovable = true;

  #boot.loader.grub.mirroredBoots = [
  #  { devices = [ "/dev/disk/by-uuid/5D35-7F32" ];
  #    path = "/boot-fallback"; }
  #];
  boot.supportedFilesystems = [ "zfs" ];
  # ZFS uses a stable host ID to guard pool ownership across machines.
  networking.hostId = "6dc72d90";

  boot = {
    #kernelParams = [ "ip=144.76.176.22::144.76.176.31:255.255.255.224::enp6s0:none" ]; # Use if dhcp not available.
    initrd = {
      # Load the on-board Intel NIC before userspace for remote ZFS unlocking.
      kernelModules = [ "igb" ];
      network = {
        # Permit remote access while the initrd waits for ZFS unlocking.
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
      systemd.services.zfs-setup-root-profile = {
        description = "Prepare root .profile for ZFS unlocking via SSH";
        wantedBy = [ "initrd.target" ];
        before = [ "initrd-root-fs.target" ];
        unitConfig.DefaultDependencies = false;
        script = ''
          mkdir -p /var/empty
          echo "systemd-tty-ask-password-agent --watch" > /var/empty/.profile
        '';
        serviceConfig.Type = "oneshot";
      };
    };
  };
}
