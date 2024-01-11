{ pkgs, config, ... }:

{
  imports = [
    ./hardware.nix
    #./nginx.nix
  ];

  environment.systemPackages = with pkgs; [
  	mc-monitor
  ];

  zramSwap.enable = true;

  networking = {

    firewall = {
      enable = true;
      allowedTCPPorts = [ 80 443 4443 27000 2022 25565 ];
      allowedUDPPorts = [ 25565 ];
      interfaces."wg0" = {
      	allowedTCPPortRanges = [ 
      	  {from = 25600; to = 26001;} #Minecraft Servers
      	];
      	allowedUDPPortRanges = [
      	  {from = 25600; to = 26001;} #Minecraft Servers (voice chats, etc.)
      	];
      };
    };
  
    networkmanager.enable = false;
    useDHCP = true;

    nameservers = [ "9.9.9.9" ];
  };

  services.nginx = {
    enable = true;
    virtualHosts."enderdragon-wings-node" = {
      serverName = "enderdragon.the-inbetween.net";
      forceSSL = true;
      enableACME = true;
      locations."/".extraConfig = ''
        proxy_set_header   X-Forwarded-For $remote_addr;
        proxy_set_header   Host $host;
        proxy_set_header Upgrade websocket;
        proxy_set_header Connection Upgrade;
        proxy_pass         "http://127.0.0.1:4443";
      '';
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
      outline = {
      	enable = true;
      	port = 23231;
      	url = "wiki.the-inbetween.net";
      };
      ssh_server.enable = true;
      wireguard.client = {
      	enable = true;
      	clientIP = "192.168.10.7";
      };
      pterodactyl = {
        panel.enable = true;
        manage.enable = true;
        wings = {
          enable = true;
          pkg = (builtins.getFlake "github:TeamMatest/nix-wings/2de9ee5f2bf8b8d2eeb214ba272a1e7e2cbe7ae0").packages.x86_64-linux.default;
        };
      };
    };
  };


  boot.loader.grub.enable = true;
  boot.loader.grub.efiSupport = true;
  boot.loader.grub.device = "nodev";
  boot.loader.grub.efiInstallAsRemovable = true;

  boot.loader.grub.mirroredBoots = [
    { devices = [ "/dev/disk/by-uuid/5DB4-0006" ];
      path = "/boot-fallback"; }
  ];
  boot.supportedFilesystems = [ "zfs" ];
  networking.hostId =   "8f291650";
  
  networking.hostName = "enderdragon";

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
