{ lib, pkgs, config, ... }:

{
  imports = [ 
    ./hardware.nix 
  ];

  zramSwap.enable = true;

  networking.interfaces.enp5s0.useDHCP = true;

  shulker = {
    profiles.server.enable = true;
    modules = {
      user.home = ./home.nix;
      impermanence.enable = true;
      #wireguard.enable = true;
      headscale = {
        enable = true;
        port = 23230;
        adminPort = 23231;
        baseUrl = "shulker.link";
        subDomain = "vpn";
      };
      pocket-id = {
        enable = true;
        baseUrl = "shulker.link";
        subDomain = "sso";
        port = 23232;
      };
      oauth2-proxy = {
        enable = true;
        baseUrl = "shulker.link";
        subDomain = "auth";
        port = 23233;
        oidcIssuer = "https://sso.shulker.link";
        oidcClientID = "92b91b09-c87b-4c34-abfa-16b52bb67ad3";
      };
      gitea = {
        enable = true;
        impermanence = true;
        baseUrl = "shulker.link";
        subDomain = "git";
        httpPort = 23236;
      };
    };
  };

  boot.loader.grub.enable = true;
  boot.loader.grub.efiSupport = true;
  boot.loader.grub.device = "nodev";
  boot.loader.grub.efiInstallAsRemovable = true;

  boot.loader.grub.mirroredBoots = [
    {
      devices = [ "/dev/disk/by-uuid/CBA2-80CB" ];
      path = "/boot-fallback";
    }
  ];
  boot.supportedFilesystems = [ "zfs" ];
  networking.hostId = "02789429";

  systemd.services."docker-pocket-id".wantedBy = [ "coder.service" "headscale.service" "gitea.service" ];
  
  boot = {
    #kernelParams = [ "ip=144.76.176.22::144.76.176.31:255.255.255.224::enp6s0:none" ]; # Use if dhcp not available.
    initrd = {
      kernelModules = [ "r8169" ]; # Check module with "lspci -v" -> driver in use for the ethernet adapter.
      network = {
        enable = true;
        ssh = {
          enable = true;
          port = 2222;
          hostKeys = [ "/nix/persist/etc/secrets/initrd/ssh_host_ed25519_key" ];
          authorizedKeys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOcuA0ZxQyqfHlWrbdVT9Hu7/IQwZuh4aQa6X1gIHOSV" ];
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
