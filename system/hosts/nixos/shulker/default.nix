{
  ...
}:

{
  imports = [
    ./hardware.nix
  ];

  zramSwap.enable = true;

  shulker = {
    system = {
      profiles.server.enable = true;
      modules = {
        impermanence.enable = true;
        backup.enable = true;
        pangolin = {
          enable = true;
          impermanence = true;
        };
        newt = {
          enable = true;
          endpoint = "https://proxy.amphibian.network";
        };
        pelican = {
          panel = {
            enable = true;
            impermanence = true;
            baseUrl = "amphibian.network";
            subDomain = "panel";
            port = 23236;
          };
          wings = {
            enable = true;
            impermanence = true;
            baseUrl = "amphibian.network";
            port = 23237;
          };
        };
        nextcloud = {
          enable = true;
          impermanence = true;
          baseUrl = "amphibian.network";
          mainSubDomain = "cloud";
          aioSubDomain = "aio";
          mainPort = 23238;
          aioPort = 23239;
        };
      };
    };
    users.conquerix.enable = true;
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
        postCommands = ''
          cat <<EOF > /root/.profile
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
