{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.modules.soft-serve;
in
{
  options.shulker.modules.soft-serve = {
    enable = mkEnableOption "Enable soft serve service";
    path = mkOption {
    	description = ''Path of repos directory'';
    	type = types.str;
    	default = "/var/lib/soft-serve";
    };
  };

  config = mkIf cfg.enable {

    environment = mkIf (config.shulker.modules.impermanence.enable) {
      systemPackages = [ pkgs.soft-serve ];
      persistence."/nix/persist".directories = [{ directory = cfg.path; user = "git"; group = "git"; mode = "u=rw,g=rw,o="; }];
    };

    users.groups.git.gid = config.ids.gids.git;
    users.users.git = {
      description = "Git Daemon User";
      createHome  = true;
      home        = cfg.path;
      group       = "git";
      uid         = config.ids.uids.git;
    };

    systemd.services.soft-serve = {
      after = ["network.target"];
      wantedBy = ["default.target"];
      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = 1;
        ExecStart = "${pkgs.soft-serve}/bin/soft serve";
      };
      environment = {
      	SOFT_SERVE_PORT = "23231";
      	SOFT_SERVE_BIND_ADDRESS = "0.0.0.0";
      	SOFT_SERVE_KEY_PATH = "${cfg.path}/key/ssh_ed25519";
      	SOFT_SERVE_REPO_PATH = "${cfg.path}/repos";
      	SOFT_SERVE_HOST = "git.shulker.fr";
      };
    };
  };
}
