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
        oidcIssuer = "https://sso.shulker.link";
        oidcClientID = "eef19321-984e-4086-9b93-8d4c905f7ca9";
      };
      pocket-id = {
        enable = true;
        baseUrl = "shulker.link";
        subDomain = "sso";
        port = 23232;
      };
      coder = {
        enable = true;
        baseUrl = "shulker.link";
        subDomain = "coder";
        listenAddresses = [ "100.64.0.5" ];
        port = 23234;
        oidcIssuer = "https://sso.shulker.link";
        oidcClientID = "04adfe9b-5974-44cd-96ce-f4f315cb5357";
      };
      searx = {
        enable = true;
        port = 23235;
        baseUrl = "shulker.link";
        subDomain = "search";
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
