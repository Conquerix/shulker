{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.shulker.system.modules.containers;
in
{
  options.shulker.system.modules.containers.enable =
    lib.mkEnableOption "Docker-backed OCI containers";

  config = lib.mkIf cfg.enable {
    virtualisation.oci-containers.backend = "docker";
    virtualisation.docker = {
      enable = true;
      enableOnBoot = true;
      autoPrune.enable = true;
    };

    environment.systemPackages = with pkgs; [
      docker-compose
      lazydocker
    ];
  };
}
