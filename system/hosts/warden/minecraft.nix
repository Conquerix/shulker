{ inputs, ... }:
{
  config.virtualisation.oci-containers.containers = {
  	minecraft-VH2 = {
  	  image = "itzg/minecraft-server:java8-jdk";
  	  ports = [ "25501:25565" "25511:25575" ];
  	  volumes = [
  	  	"/storage/fast/Minecraft-Servers/Vault-Hunters-2/modpacks:/modpacks"
  	  	"/storage/fast/Minecraft-Servers/Vault-Hunters-2/data:/data"
  	  ];
  	  environment = {
  	    EULA = "TRUE";
  	  	TYPE = "CURSEFORGE";
  	  	CF_SERVER_MOD = "/modpacks/VaultHunters.zip";
  	  	CF_BASE_DIR = "/data";
  	  };
  	};
  };
}
