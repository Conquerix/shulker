{ pkgs, config, ... }:

{
  imports = [
    ./hardware.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.supportedFilesystems = [ "zfs" ];
  networking.hostId =   "f58f5990";

  networking.hostName = "vindicator";

  boot = {
    kernelParams = [ "ip=141.94.96.139::141.94.96.254:255.255.255.0::enp1s0f0:none" ];
    initrd = {
      kernelModules = [ "ixgbe" ];
#      preLVMCommands = lib.mkOrder 400 "sleep 1";
      network = {
        enable = true;
        ssh = {
          enable = true;
          port = 2222;
          hostKeys = [ /nix/persist/etc/secrets/initrd/ssh_host_ed25519_key ];
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


  zramSwap.enable = true;

  networking = {

    firewall = {
      enable = true;
      allowedTCPPorts = [ 80 443 4443 27000 2022 ];
      allowedTCPPortRanges = [ 
        {from = 25600; to = 26001;} #Minecraft Servers
      ];
      allowedUDPPortRanges = [
        {from = 25600; to = 26001;} #Minecraft Servers (voice chats, etc.)
      ];

    };

    networkmanager.enable = false;
    useDHCP = false;

    nameservers = [ "9.9.9.9" ];

    interfaces.enp1s0f0 = {
      useDHCP = false;

      ipv4.addresses = [{
        address = "141.94.96.139";
        prefixLength = 32;
      }];

      ipv6.addresses = [{
        address = "2001:41d0:403:478b::";
        prefixLength = 64;
      }];
    };

    defaultGateway = {
      address = "141.94.96.254";
      interface = "enp1s0f0";
    };
    defaultGateway6 = {
      address = "2001:41d0:0403:47ff:00ff:00ff:00ff:00ff";
      interface = "enp1s0f0";
    };
  };

  shulker = {
    modules = {
      user.home = ./home.nix;
      docker.enable = true;
      impermanence = {
        enable = true;
        docker = true;
      };
      ssh_server = {
        enable = true;
      };
      wireguard.client = {
        enable = true;
        clientIP = "192.168.10.6";
      };
      pterodactyl = {
        wings = {
          enable = true;
          pkg = (builtins.getFlake "github:TeamMatest/nix-wings/2de9ee5f2bf8b8d2eeb214ba272a1e7e2cbe7ae0").packages.x86_64-linux.default;
        };
      };
    };
  };
}
