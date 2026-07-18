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
            image = "docker.io/library/nginx:alpine@sha256:4a73073bd557c65b759505da037898b61f1be6cbcc3c2c3aeac22d2a470c1752";
            volumes = [
              "${statePath}:/var/www:ro"
            ];
            ports = [
              "${cfg.bindAddress}:${toString port}:80/tcp"
            ];
            log-driver = "journald";
            # Inject Nginx configuration to point to the git-sync symlink
            cmd = [
              "/bin/sh"
              "-c"
              ''
                echo 'server { listen 80; root /var/www/site${nginxSubPath}; location / { try_files $uri $uri/ =404; } }' > /etc/nginx/conf.d/default.conf
                exec /docker-entrypoint.sh nginx -g "daemon off;"
              ''
            ];
          };

          syncContainer = nameValuePair "git-pages-${name}-sync" {
            image = "registry.k8s.io/git-sync/git-sync:v4.0.0@sha256:ad48c2dd8f5ae73e783c4a55bedb4cc13d51d347d157e6564c4debfd0fbd429d";
            volumes = [
              "${statePath}:/git:rw"
            ];
            # Fix Permission Denied: Run as root so it can write to the host-mounted volume
            user = "root:root";
            # Fix v4 Pathing: Use explicit v4 arguments instead of deprecated env vars
            cmd = [
              "--repo=${repo.url}"
              "--branch=${repo.branch}"
              "--period=${pullInt}"
              "--link=site" # Replaces the old GITSYNC_DEST
              "--root=/git" # Explicitly set the root to match our volume mount
            ];
            log-driver = "journald";
          };
        in
        if repo.sync then
          [
            syncContainer
            webContainer
          ]
        else
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
    bindAddress = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Host address on which to publish static sites.";
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
