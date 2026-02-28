{
  config,
  lib,
  pkgs,
  ...
}:

with lib;
let
  cfg = config.shulker.system.modules.ollama;
in
{
  options.shulker.system.modules.ollama = {
    enable = mkEnableOption "Enable ollama service";
    impermanence = mkEnableOption "Whether to enable impermanence on state directories.";
    port = mkOption {
      type = types.port;
      default = 11434;
      description = "Default internal port for the ollama API.";
    };
    host = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Address to bind the ollama API to.";
    };
    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/ollama";
      description = "State directory for ollama models and data.";
    };
  };

  config = mkIf cfg.enable {

    services.ollama = {
      enable = true;
      port = cfg.port;
      host = cfg.host;
      home = cfg.stateDir;
      openFirewall = true;
      package = pkgs.ollama-cuda;
      user = "ollama";
      group = "ollama";
    };

    environment.persistence = mkIf cfg.impermanence {
      "/nix/persist".directories = [
        {
          directory = cfg.stateDir;
          mode = "u=rwx,g=rx,o=";
          user = "ollama";
          group = "ollama";
        }
      ];
    };

    shulker.system.modules.backup.dirs = [ cfg.stateDir ];
  };
}
