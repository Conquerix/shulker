{ pkgs, ... }:

{
  imports = [
    ./hardware.nix
#    ./minecraft.nix
#	./turbopilot.nix
  ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # For zfs.
  networking.hostId = "2118dc3b";

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 23080 ];
  };

  services.transmission = {
    enable = true;
    settings = {
      download-dir = "/storage/fast/torrent/";
      incomplete-dir = "/storage/fast/torrent/.incomplete/";
      incomplete-dir-enabled = true;
      rpc-whitelist = "127.0.0.1,192.168.*.*";
    };
  };

  environment.systemPackages = with pkgs; [
    stig
  ];

  services.nginx = {
    enable = true;
    streamConfig = ''
      upstream idrac {
        server 192.168.1.10:443;
      }

      server {
        listen 23080;
        proxy_pass idrac;
      }
    '';
  };
  

  shulker = {
    modules = {
      user.home = ./home.nix;
      docker.enable = true;
      impermanence.enable = true;
      ssh_server = {
        enable = true;
      };
      wireguard.client = {
      	enable = true;
      	clientIP = "192.168.10.2";
      };
      pufferpanel = {
      	enable = true;
      	webPort = 24480;
      	sftpPort = 24457;
      	companyName = "QSMP Fan Server";
      	storagePath = "/storage/fast/pufferpanel";
      };
    };
  };
}
