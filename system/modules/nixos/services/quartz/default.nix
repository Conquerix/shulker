# Private Quartz publication of explicitly selected agent knowledge directories.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.shulker.system.modules.quartz;
  agents = pkgs.writeText "quartz-agents.json" (
    builtins.toJSON (
      lib.mapAttrsToList (id: agent: {
        inherit id;
        inherit (agent) name;
      }) cfg.agents
    )
  );
  nginx = pkgs.writeText "quartz-nginx.conf" ''
    pid /tmp/nginx.pid;
    events {}
    http {
      include /etc/nginx/mime.types;
      access_log off;
      error_log /dev/stderr warn;
      client_body_temp_path /tmp/client;
      proxy_temp_path /tmp/proxy;
      fastcgi_temp_path /tmp/fastcgi;
      uwsgi_temp_path /tmp/uwsgi;
      scgi_temp_path /tmp/scgi;
      server {
        listen 8080;
        root /site/current;
        index index.html;
        add_header Cache-Control "private, no-store" always;
        add_header X-Robots-Tag "noindex, nofollow" always;
        location / { try_files $uri $uri.html $uri/ =404; }
      }
    }
  '';
in
{
  options.shulker.system.modules.quartz = {
    enable = lib.mkEnableOption "private agent knowledge publication";
    impermanence = lib.mkEnableOption "persistent Quartz image archives and generated site";
    image = lib.mkOption {
      type = lib.types.str;
      description = "Pinned upstream Quartz builder image.";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 23251;
    };
    publicUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://notes.shulker.link";
    };
    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/quartz";
    };
    agents = lib.mkOption {
      default = { };
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, ... }: {
            options = {
              name = lib.mkOption {
                type = lib.types.str;
                default = name;
              };
              contentDir = lib.mkOption {
                type = lib.types.str;
                description = "This agent's published knowledge directory, readable by UID 10000.";
              };
            };
          }
        )
      );
    };
  };
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.agents != { };
        message = "Quartz needs at least one agent knowledge directory.";
      }
      {
        assertion = lib.all (id: builtins.match "[a-z0-9]+(-[a-z0-9]+)*" id != null) (
          builtins.attrNames cfg.agents
        );
        message = "Quartz agent IDs must be lowercase URL-safe names.";
      }
      {
        assertion = lib.hasPrefix "sha256:" cfg.image || lib.hasInfix "@sha256:" cfg.image;
        message = "Quartz requires a pinned image ID or registry digest.";
      }
    ];
    shulker.system.modules.containers.enable = true;
    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0700 root root -"
      "d ${cfg.stateDir}/site 0700 hermes hermes -"
      "d ${cfg.stateDir}/images 0700 root root -"
    ];
    virtualisation.oci-containers.containers = {
      quartz-build = {
        image = cfg.image;
        pull = "missing";
        user = "10000:10000";
        cmd = [
          "/bin/sh"
          "/run/quartz-publish.sh"
        ];
        environment = {
          QUARTZ_IMAGE = cfg.image;
          QUARTZ_BASE_URL = lib.removePrefix "https://" (lib.removePrefix "http://" cfg.publicUrl);
          UPDATE_INTERVAL = "60";
        };
        volumes = [
          "${cfg.stateDir}/site:/output:rw"
          "${agents}:/run/quartz-agents.json:ro"
          "${./publish.sh}:/run/quartz-publish.sh:ro"
          "${./index.mjs}:/run/quartz-index.mjs:ro"
          "${./quartz.config.ts}:/usr/src/app/quartz.config.ts:ro"
        ]
        ++ lib.mapAttrsToList (id: agent: "${agent.contentDir}:/notes/${id}:ro") cfg.agents;
        extraOptions = [
          "--network=none"
          "--read-only"
          "--cap-drop=ALL"
          "--security-opt=no-new-privileges"
          "--memory=2g"
          "--cpus=2"
          "--pids-limit=256"
          "--tmpfs=/tmp:rw,size=256m,uid=10000,gid=10000"
          "--tmpfs=/usr/src/app/quartz/.quartz-cache:rw,size=128m,uid=10000,gid=10000"
        ];
      };
      quartz-web = {
        image = "docker.io/library/nginx:alpine@sha256:4a73073bd557c65b759505da037898b61f1be6cbcc3c2c3aeac22d2a470c1752";
        pull = "missing";
        user = "10000:10000";
        entrypoint = "nginx";
        cmd = [
          "-c"
          "/run/quartz-nginx.conf"
          "-g"
          "daemon off;"
        ];
        ports = [ "127.0.0.1:${toString cfg.port}:8080" ];
        volumes = [
          "${cfg.stateDir}/site:/site:ro"
          "${nginx}:/run/quartz-nginx.conf:ro"
        ];
        extraOptions = [
          "--read-only"
          "--cap-drop=ALL"
          "--security-opt=no-new-privileges"
          "--memory=128m"
          "--cpus=1"
          "--pids-limit=64"
          "--tmpfs=/tmp:rw,size=32m,uid=10000,gid=10000"
        ];
      };
    };
    systemd.services.docker-quartz-build.unitConfig.RequiresMountsFor = [
      cfg.stateDir
    ]
    ++ lib.mapAttrsToList (_: agent: agent.contentDir) cfg.agents;
    systemd.services.docker-quartz-web = {
      after = [ "docker-quartz-build.service" ];
      unitConfig.RequiresMountsFor = [ cfg.stateDir ];
    };
    environment.persistence = lib.mkIf cfg.impermanence {
      "/nix/persist".directories = [
        {
          directory = cfg.stateDir;
          mode = "0700";
        }
      ];
    };
    # Source notes are backed up by their agent; generated HTML is disposable.
    shulker.system.modules.backup.dirs = [ "${cfg.stateDir}/images" ];
  };
}
