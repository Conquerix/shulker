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
    flatten (
      imap0 (
        i: repo:
        let
          name = sanitizeName repo.name;
          port = if repo.port != 0 then repo.port else (cfg.basePort + i);
          statePath = "${cfg.stateDir}/${name}";
          pullInt = if repo.pullInterval != null then repo.pullInterval else cfg.pullInterval;

          # Optional subpath logic for Nginx root
          nginxSubPath = if repo.path != "" then "/${repo.path}" else "";

          webContainer = nameValuePair "git-pages-${name}-web" {
            image = "docker.io/library/nginx:alpine";
            volumes = [
              # Mount the parent directory so Nginx can follow the symlink dynamically
              "${statePath}:/var/www:ro"
            ];
            ports = [
              "${toString port}:80/tcp"
            ];
            log-driver = "journald";
            # Generate a minimal Nginx config to serve the correct path and follow the symlink
            cmd = [
              "/bin/sh"
              "-c"
              ''
                echo 'server { listen 80; root /var/www/site${nginxSubPath}; location / { try_files $uri $uri/ =404; } }' > /etc/nginx/conf.d/default.conf
                exec nginx -g "daemon off;"
              ''
            ];
          };

          syncContainer = nameValuePair "git-pages-${name}-sync" {
            image = "registry.k8s.io/git-sync/git-sync:v4.0.0";
            volumes = [
              "${statePath}:/tmp/git:rw"
            ];
            environment = {
              GITSYNC_REPO = repo.url;
              GITSYNC_BRANCH = repo.branch;
              # git-sync creates a symlink named after GITSYNC_DEST pointing to the active revision
              GITSYNC_DEST = "site";
              GITSYNC_PERIOD = pullInt;
            };
            log-driver = "journald";
          };
        in
        if repo.sync then
          # If sync is true, return BOTH containers
          [
            syncContainer
            webContainer
          ]
        else
          # Otherwise just the web container
          [ webContainer ]
      ) cfg.repos
    )
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
        # Only require/wait for sync if this repo actually uses git-sync
        after = optional repo.sync "docker-git-pages-${name}-sync.service";
        requires = optional repo.sync "docker-git-pages-${name}-sync.service";
        partOf = [ "docker-compose-git-pages-root.target" ];
        wantedBy = [ "docker-compose-git-pages-root.target" ];
      }
    ) cfg.repos
  );

  syncSystemdServices = listToAttrs (
    flatten (
      map (
        repo:
        let
          name = sanitizeName repo.name;
        in
        optional repo.sync (
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
        )
      ) cfg.repos
    )
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
