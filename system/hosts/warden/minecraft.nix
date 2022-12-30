{ inputs, ... }:
{
  config.virtualisation.oci-containers.containers = {
  	minecraft-VH2 = {
  	  image = "itzg/minecraft-server:java8-jdk";
  	  ports = [ "25501:25501" "25511:25511" "25521:25521/udp"];
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

  	"minecraft-Project-Paper-1-19" = {
  	  image = "itzg/minecraft-server";
  	  ports = [ "25502:25502" "25512:25512" "25522:25522/udp" "25532:25532"];
  	  volumes = [
  	  	"/storage/fast/Minecraft-Servers/Project-Paper-1.19/data:/data"
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
