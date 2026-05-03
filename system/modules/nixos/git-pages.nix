{
  lib,
  config,
  ...
}:

with lib;
let
  cfg = config.shulker.system.modules.git-pages;

  # Generate a safe container name from the repo name
  sanitizeName = name: replaceStrings [ "/" ":" "." ] [ "_" "_" "_" ] name;

  # Build container and service attrs from the repo list
  containers = listToAttrs (
    imap0 (
      i: repo:
      let
        name = sanitizeName repo.name;
        port = if repo.port != 0 then repo.port else (cfg.basePort + i);
        statePath = "${cfg.stateDir}/${name}";
        pullInt = if repo.pullInterval != null then repo.pullInterval else cfg.pullInterval;
      in
      if repo.sync then
        # Git-sync container
        nameValuePair "git-pages-${name}-sync" {
          image = "registry.k8s.io/git-sync/git-sync:v4.0.0";
          volumes = [
            "${statePath}/tmp:/tmp/git:rw"
          ];
          environment = {
            GITSYNC_REPO = repo.url;
            GITSYNC_BRANCH = repo.branch;
            GITSYNC_DEST = "${repo.path}/html";
            GITSYNC_PERIOD = pullInt;
          };
          log-driver = "journald";
          extraOptions = [
            "--network-alias=git-pages-${name}-sync"
          ];
        }
      else
        # Nginx web container
        nameValuePair "git-pages-${name}-web" {
          image = "docker.io/library/nginx:alpine";
          volumes = [
            "${statePath}/html:/usr/share/nginx/html:ro"
          ];
          ports = [
            "${toString port}:80/tcp"
          ];
          log-driver = "journald";
          extraOptions = [
            "--network-alias=git-pages-${name}-web"
          ];
        }
    ) cfg.repos
  );

  systemdServices = listToAttrs (
    imap0 (
      i: repo:
      let
        name = sanitizeName repo.name;
      in
      nameValuePair "docker-git-pages-${name}-web" {
        serviceConfig = {
          Restart = mkOverride 90 "always";
          RestartMaxDelaySec = mkOverride 90 "1m";
          RestartSec = mkOverride 90 "100ms";
          RestartSteps = mkOverride 90 9;
        };
        after = [ "docker-git-pages-${name}-sync.service" ];
        requires = [ "docker-git-pages-${name}-sync.service" ];
        partOf = [ "docker-compose-git-pages-root.target" ];
        wantedBy = [ "docker-compose-git-pages-root.target" ];
      }
    ) cfg.repos
  );

  syncSystemdServices = listToAttrs (
    map (
      repo:
      let
        name = sanitizeName repo.name;
      in
      nameValuePair "docker-git-pages-${name}-sync" {
        serviceConfig = {
          Restart = mkOverride 90 "always";
          RestartMaxDelaySec = mkOverride 90 "1m";
          RestartSec = mkOverride 90 "100ms";
          RestartSteps = mkOverride 90 9;
        };
        partOf = [ "docker-compose-git-pages-root.target" ];
        wantedBy = [ "docker-compose-git-pages-root.target" ];
      }
    ) cfg.repos
  );
in
{
  options.shulker.system.modules.git-pages = {
    enable = mkEnableOption "Enable git-pages static site service";
    impermanence = mkEnableOption "Whether to enable impermanence on state directories.";
    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/git-pages";
      description = "Base state directory for all repos.";
    };
    basePort = mkOption {
      type = types.port;
      default = 3000;
      description = "Starting port number for repos without explicit port.";
    };
    pullInterval = mkOption {
      type = types.str;
      default = "60s";
      description = "Default how often to check for updates.";
    };
    repos = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            name = mkOption {
              type = types.str;
              description = "Unique name for this repo (used for container names).";
            };
            url = mkOption {
              type = types.str;
              description = "URL of the Git repository to deploy.";
            };
            branch = mkOption {
              type = types.str;
              default = "main";
              description = "Branch to deploy from.";
            };
            path = mkOption {
              type = types.str;
              default = "";
              description = "Subdirectory within the repo to serve (empty = repo root).";
            };
            port = mkOption {
              type = types.port;
              default = 0;
              description = "Port to serve on (0 = auto-assigned from basePort).";
            };
            pullInterval = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Override pull interval for this repo.";
            };
            sync = mkOption {
              type = types.bool;
              default = true;
              description = "Whether this repo needs git-sync (true) or is just a web server.";
            };
          };
        }
      );
      default = [ ];
      description = "List of repositories to deploy.";
    };
  };

  config = mkIf cfg.enable {

    virtualisation.oci-containers.containers = containers;
    systemd.services = systemdServices // syncSystemdServices;

    # Root service
    systemd.targets."docker-compose-git-pages-root" = {
      unitConfig = {
        Description = "Git-Pages Static Site containers";
      };
      wantedBy = [ "multi-user.target" ];
    };

    environment.persistence = mkIf cfg.impermanence {
      "/nix/persist".directories = [
        {
          directory = cfg.stateDir;
          mode = "u=rwx,g=rx,o=";
        }
      ];
    };

    shulker.system.modules.backup.dirs = [ cfg.stateDir ];
  };
}
