{ ... }:

let
  # Vault (Paper plugin)
  vault_id = "34315";

  # LuckPerms (Paper/Velocity plugin)
  luckperms_id = "28140";

  # CMILib (Paper plugin)
  cmilib_id = "87610";

  # WildTools (Paper plugin)
  wildtools_url = "https://bg-software.com/downloads//WildTools-2022.7.jar";

  # WildLoaders (Paper plugin)
  wildloaders_url = "https://bg-software.com/downloads//WildLoaders-2022.7.jar";

  # WildStacker (Paper plugin)
  wildstacker_url = "https://bg-software.com/downloads//WildStacker-2022.6.jar";

  # WildChest (Paper plugin)
  wildchests_url = "https://bg-software.com/downloads//WildChests-2022.7.jar";

  # Tardis (Paper plugin)
  tardis_url = "http://tardisjenkins.duckdns.org:8080/view/TARDIS/job/TARDIS/lastStableBuild/artifact/target/TARDIS.jar";

  # Tardis Chunk Generator (Paper plugin)
  tardiscg_url = "http://tardisjenkins.duckdns.org:8080/view/TARDIS/job/TARDISChunkGenerator/lastStableBuild/artifact/target/TARDISChunkGenerator.jar";

in

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
  	  ports = [ "30001:25565" ];
  	  volumes = [
  	  	"/storage/fast/Minecraft-Servers/Project-Paper-1.19/data:/data"
        "/storage/fast/Minecraft-Servers/Project-Paper-1.19/plugins:/plugins"
  	  ];
  	  environment = {
  	    EULA = "TRUE";
  	  	TYPE = "PAPER";
  	  	ONLINE_MODE = "FALSE";
  	  	SPIGET_RESOURCES = "${vault_id},${luckperms_id},${cmilib_id}";
  	  	MODS = "${wildtools_url},${wildstacker_url},${wildloaders_url},${wildchests_url},${tardis_url},${tardiscg_url}";
  	  	USE_AIKAR_FLAGS = "true";
  	  	MEMORY = "16G";
  	  	ENABLE_WHITELIST = "false";
  	  	OPS = "Conquerix";
      };
  	};

  	minecraft-limbo = {
      image = "itzg/minecraft-server";
      ports = [ "30000:30000" ];
      environment = {
        TYPE = "LIMBO";
        EULA = "true";
      };
      volumes = [
        "/storage/fast/Minecraft-Servers/limbo/data:/data"
      ];
    };
  };
}
