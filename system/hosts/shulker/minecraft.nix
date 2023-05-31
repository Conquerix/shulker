{ ... }:

let

  # Advanced Server List (Velocity plugin)
  asl_url = "https://cdn.modrinth.com/data/xss83sOY/versions/zcLl7lHV/AdvancedServerList-Velocity-1.9.0.jar";

  # Velocity Vanish (Velocity/Paper plugin)
  vv_url = "https://cdn.modrinth.com/data/hkzyeLcD/versions/lR4SoRpU/VelocityVanish%20v3.10.1.jar";

  # Velocity Report (Velocity/Paper plugin)
  vr_url = "https://cdn.modrinth.com/data/mqGjZEIE/versions/Y9341eir/VelocityReport%20v3.6.0.jar";

  # Enhanced Velocity (Velocity plugin)
  ev_url = "https://cdn.modrinth.com/data/hYGBbRYo/versions/bDaDWhdY/EnhancedVelocity%20v1.1.1.jar";

  # Maintenance Mode (Velocity/Paper plugin, not same jar for different backends)
  mtn_url = "https://github.com/kennytv/Maintenance/releases/download/4.0.1/MaintenanceVelocity.jar";

  # Server GUI (Velocity plugin, requires protocolize just below)
  sgui_url = "https://github.com/Matt-MX/ServerGUI/releases/download/2.0/servergui-2.0-jar-with-dependencies.jar";

  # Protocolize (Velocity plugin)
  ptcl_url = "https://github.com/Exceptionflug/protocolize/releases/download/v2.2.4/protocolize-velocity.jar";

  # ViaVersion (Velocity plugin)
  vver_url = "https://github.com/ViaVersion/ViaVersion/releases/download/4.5.1/ViaVersion-4.5.1.jar";

  # ViaBackwards (Velocity plugin)
  vb_url = "https://github.com/ViaVersion/ViaBackwards/releases/download/4.5.1/ViaBackwards-4.5.1.jar";

  # LuckPerms (Velocity/Paper plugin)
  lp_url = "https://download.luckperms.net/1464/velocity/LuckPerms-Velocity-5.4.56.jar";

  # CMI Bungee (Velocity plugin)
  cmib_url = "https://www.zrips.net/cmib/download.php?file=CMIB-1.0.2.2.jar";

in

{


  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 25501 25565 ];
    allowedUDPPorts = [ 25521 ];
  };

  security.acme.acceptTerms = true;

  services.nginx = {
    enable = true;
    streamConfig = ''
      upstream warden-minecraft-VH2 {
        server 192.168.10.2:25501;
      }

      upstream warden-minecraft-VH2-V {
        server 192.168.10.2:25521;
      }
      
      server {
        listen 25501;
        proxy_pass warden-minecraft-VH2;
      }

      server {
        listen 25521 udp;
        proxy_pass warden-minecraft-VH2-V;
      }
    '';
  };

  virtualisation.oci-containers.containers = {
  	minecraft-velocity = {
      image = "itzg/bungeecord";
      ports = [ "25565:25577" ];
      environment = {
      	TYPE = "VELOCITY";
      	debug = ''"false"'';
      	ENABLE_RCON = ''"true"'';
      	JVM_XX_OPTS = "-XX:+UseG1GC -XX:G1HeapRegionSize=4M -XX:+UnlockExperimentalVMOptions -XX:+ParallelRefProcEnabled -XX:+AlwaysPreTouch -XX:MaxInlineLevel=15";
      	#MEMORY = "2048m";
      	PLUGINS = "${asl_url},${vv_url},${vr_url},${ev_url},${mtn_url},${sgui_url},${ptcl_url},${vver_url},${vb_url},${lp_url},${cmib_url}";
      };
      volumes = [
      	"/docker/minecraft-velocity/server:/server"
      	"/docker/minecraft-velocity/config:/config"
      	"/docker/minecraft-velocity/plugins:/plugins"
      ];
  	};
  };
}
