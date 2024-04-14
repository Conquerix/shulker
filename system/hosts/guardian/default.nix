{pkgs, ... }:

{
  imports = [ ./hardware.nix ];

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 443 30080 30443 31443 ];
  };

  virtualisation.oci-containers.containers."kasm" = {
  	autoStart = true;
  	image = "lscr.io/linuxserver/kasm:latest";
  	ports = [
  	  "3000:3000"
      "443:443"
    ];
    environment = {
      KASM_PORT = "443";
    };
    #volumes = [
    #  "/:/opt"
    #  "/:/profiles"
    #];
    extraOptions = [
      "--privileged=true"
#      "--gpus=all"
    ];
  };

  services.nginx = {
    enable = true;
    streamConfig = ''
      upstream idrac {
        server 192.168.1.20:80;
      }

      server {
        listen 30080;
        proxy_pass idrac;
      }

      upstream idrac-ssl {
        server 192.168.1.20:443;
      }

      server {
        listen 30443;
        proxy_pass idrac-ssl;
      }

      upstream livebox {
        server 192.168.1.1:443;
      }

      server {
        listen 31443;
        proxy_pass livebox;
      }
    '';
  };
  

  boot.loader = {
  efi = {
    canTouchEfiVariables = true;
    efiSysMountPoint = "/boot";
    };
  grub = {
    enable = true;
    devices = ["nodev"];
    efiSupport = true;
    };
  };

  shulker = {
    modules = {
      user.home = ./home.nix;
      impermanence = {
        enable = true;
        home = true;
        docker = true;
      };
      docker.enable = true;
      yubikey.enable = true;
      ssh_server.enable = true;
      wireguard.enable = true;
      wireguard.client = {
      	enable = true;
      	clientIP = "192.168.10.5";
      };
    };
  };
}
