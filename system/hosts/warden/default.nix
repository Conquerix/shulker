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
  boot.kernel.sysctl."vm.max_map_count" = 2147483642;

  # For zfs.
  networking.hostId = "2118dc3b";

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 23080 5657 24480];
    allowedTCPPortRanges = [ {from = 25500; to = 25599;} {from = 25700; to = 25799;} ];
    allowedUDPPorts = [ 25566 25568 ];
    allowedUDPPortRanges = [ {from = 25600; to = 25699;} ];
  };


  # Systemd timer/service for qsmp backups
  systemd.timers."qsmp-backups" = {
    wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*:0/15";
        Unit = "qsmp-backups.service";
      };
  };
  
  systemd.services."qsmp-backups" = {
    script = ''
      ${pkgs.rsync}/bin/rsync -P -r /storage/fast/pufferpanel/data/servers/02a242f8/simplebackups/* /storage/mass/qsmp/backups/
    '';
    serviceConfig = {
      Type = "oneshot";
      User = "root";
    };
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
      crafty_controller = {
      	enable = true;
      	webPort = 35080;
      	httpsPort = 35443;
      	storagePath = "/storage/fast/crafty-controller";
      };
    };
  };
}
