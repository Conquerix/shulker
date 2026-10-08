# Upstream all-in-one Canvas: native agent, frontend and persistent home.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.shulker.system.modules.openhands;
in
{
  options.shulker.system.modules.openhands = {
    enable = lib.mkEnableOption "OpenHands";
    impermanence = lib.mkEnableOption "persistent OpenHands data and projects";
    image = lib.mkOption {
      type = lib.types.str;
      default = "ghcr.io/openhands/agent-canvas:1.25.0@sha256:10190cdede885f74853567f4aa44b33de094139a940df75f4b204a2b6df73c57";
    };
    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/openhands-clean";
    };
    projectsDir = lib.mkOption {
      type = lib.types.str;
      default = "/srv/ai-projects";
    };
    nixStoreDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/openhands-nix";
      description = "Container-local development store; independently rebuildable from flakes.";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 23249;
    };
    publicUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://code.shulker.link";
    };
  };
  config = lib.mkIf cfg.enable {
    shulker.system.modules.containers.enable = true;
    # Match the upstream image's user; grant the human editor workspace access.
    users.groups.openhands.gid = 10001;
    users.users.openhands = {
      isSystemUser = true;
      uid = 10001;
      group = "openhands";
    };
    users.users.conquerix.extraGroups = [ "openhands" ];
    programs.git = {
      enable = true;
      config.safe.directory = "${cfg.projectsDir}/*";
    };
    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0700 openhands openhands -"
      "d ${cfg.stateDir}/home 0700 openhands openhands -"
      "d ${cfg.stateDir}/home/.openhands 0700 openhands openhands -"
      "d ${cfg.nixStoreDir} 0755 openhands openhands -"
      "d ${cfg.projectsDir} 2770 openhands openhands -"
      "a+ ${cfg.projectsDir} - - - - u:conquerix:rwx,d:u:conquerix:rwx"
    ];
    virtualisation.oci-containers.containers.openhands = {
      image = cfg.image;
      pull = "missing";
      ports = [ "127.0.0.1:${toString cfg.port}:8000" ];
      volumes = [
        "${cfg.stateDir}/home:/home/openhands:rw"
        # Override the image's child VOLUME so settings stay in the backed-up home.
        "${cfg.stateDir}/home/.openhands:/home/openhands/.openhands:rw"
        "${cfg.projectsDir}:/projects:rw"
        "${cfg.nixStoreDir}:/nix:rw"
        "${config.services.onepassword-secrets.secrets.openhandsGithubToken.path}:/run/secrets/github-token:ro"
        "${pkgs.writeText "openhands-nix.conf" ''
          experimental-features = nix-command flakes
          # The single-user store is isolated by Docker, without a host daemon.
          sandbox = false
          build-users-group =
          max-jobs = 2
          cores = 2
        ''}:/etc/nix/nix.conf:ro"
      ];
      environment = {
        HOME = "/home/openhands";
        PATH = "/home/openhands/.nix-profile/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin";
        # Let Nix packages resolve their own libraries instead of the image's.
        LD_LIBRARY_PATH = "";
        OH_ENABLE_VSCODE = "false";
        OH_ENABLE_BROWSER = "false";
        DO_NOT_TRACK = "1";
        VITE_DO_NOT_TRACK = "1";
        # Both users may create repositories inside this shared workspace.
        GIT_CONFIG_COUNT = "2";
        GIT_CONFIG_KEY_0 = "safe.directory";
        GIT_CONFIG_VALUE_0 = "/projects/*";
        # Read the scoped token on demand; keep it out of remotes and Git config.
        GIT_CONFIG_KEY_1 = "credential.https://github.com.helper";
        GIT_CONFIG_VALUE_1 = ''!f() { if [ "$1" = get ]; then printf 'username=x-access-token\npassword='; cat /run/secrets/github-token; printf '\n'; fi; }; f'';
        # The only published port is loopback; Pangolin admits only the owner.
        AGENT_CANVAS_ALLOW_LAN_SESSION_KEY = "true";
      };
      environmentFiles = [ config.services.onepassword-secrets.secrets.openhandsEnv.path ];
      extraOptions = [
        # Evaluating this fleet's flake exceeded the original 4 GiB ceiling.
        "--memory=8g"
        "--cpus=2"
        "--pids-limit=512"
      ];
    };
    services.onepassword-secrets.secrets.openhandsEnv = {
      reference = "op://Shulker/${config.networking.hostName}/OpenHands/Environment";
      services = [ "docker-openhands" ];
      mode = "0400";
    };
    services.onepassword-secrets.secrets.openhandsGithubToken = {
      reference = "op://Shulker/${config.networking.hostName}/OpenHands/GitHub API Token";
      services = [ "docker-openhands" ];
      owner = "openhands";
      group = "openhands";
      mode = "0400";
    };
    systemd.services.docker-openhands = {
      requires = [ "opnix-secrets.service" ];
      unitConfig.RequiresMountsFor = [
        cfg.stateDir
        cfg.projectsDir
        cfg.nixStoreDir
      ];
    };
    environment.persistence = lib.mkIf cfg.impermanence {
      "/nix/persist".directories = [
        {
          directory = cfg.stateDir;
          mode = "0700";
          user = "openhands";
          group = "openhands";
        }
        {
          directory = cfg.projectsDir;
          mode = "2770";
          user = "openhands";
          group = "openhands";
        }
        {
          directory = cfg.nixStoreDir;
          mode = "0755";
          user = "openhands";
          group = "openhands";
        }
      ];
    };
    shulker.system.modules.backup.dirs = [
      cfg.stateDir
      cfg.projectsDir
    ];
  };
}
