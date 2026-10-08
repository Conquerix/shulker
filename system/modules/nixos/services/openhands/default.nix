# Opt-in coding boundary: static frontend/broker on Shulker, one worker on Enderdragon.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.shulker.system.modules.openhands;
  images = import ./images.nix;
  nativeProfile = (builtins.fromJSON (builtins.readFile ./native-profile.json)).agent_profile;
  package = import ./package.nix { inherit pkgs; };
  python = pkgs.python3.withPackages (p: [ p.httpx ]);
  policy = pkgs.writeText "openhands-broker-policy.json" (
    builtins.toJSON {
      backend = cfg.broker.backendUrl;
      profile_id = cfg.broker.agentProfileId;
      uid = 10010;
      canvas = cfg.frontend.publicUrl;
    }
  );
  workerPolicy = pkgs.writeText "openhands-worker-policy.json" (
    builtins.toJSON {
      canvasOrigin = cfg.frontend.publicUrl;
    }
  );
  caddyText = ''
    {
      auto_https off
      admin off
      persist_config off
    }
    http://:23250 {
      bind 127.0.0.1
      import ${package.frontend}/script-hashes.caddy
      header Content-Security-Policy "default-src 'self'; script-src 'self' 'wasm-unsafe-eval' {http.vars.scriptHashes}; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data:; connect-src 'self' ${cfg.broker.backendUrl} ${
        lib.replaceStrings [ "https://" ] [ "wss://" ] cfg.broker.backendUrl
      }; frame-ancestors 'none'; base-uri 'self'"
      header Referrer-Policy "no-referrer"
      header X-Content-Type-Options "nosniff"
      redir / /canvas/ 302
      handle_path /canvas/* {
        root * ${package.frontend}
        try_files {path} /index.html
        file_server
      }
      respond "Not found" 404
    }
  '';
  caddyfile = pkgs.writeText "openhands-canvas.Caddyfile" caddyText;
  backup = pkgs.writeShellApplication {
    name = "openhands-backup";
    runtimeInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.util-linux
      pkgs.gnutar
      pkgs.gzip
      pkgs.systemd
    ];
    text =
      if cfg.worker.enable then
        "exec bash ${./backup.sh} docker-openhands-worker.service /var/lib/openhands-backups/worker.tar.gz /var/lib/openhands /srv/openhands/projects/shulker"
      else
        "exec bash ${./backup.sh} openhands-broker.service /var/lib/openhands-backups/broker.tar.gz /var/lib/openhands-broker";
  };
  bool = description: lib.mkEnableOption description;
  str =
    default:
    lib.mkOption {
      type = lib.types.str;
      inherit default;
    };
in
{
  options.shulker.system.modules.openhands = {
    worker = {
      enable = bool "the isolated OpenHands coding worker";
      secretReference = str "";
    };
    frontend = {
      enable = bool "the private OpenHands Canvas frontend";
      publicUrl = str "https://code.shulker.link";
      configText = lib.mkOption {
        type = lib.types.str;
        readOnly = true;
        internal = true;
      };
      configFile = lib.mkOption {
        type = lib.types.path;
        readOnly = true;
        internal = true;
      };
    };
    broker = {
      enable = bool "narrow Hermes coding delegation";
      backendUrl = str "https://coding-api.shulker.link";
      agentProfileId = str nativeProfile.id;
      secretReference = str "";
    };
  };
  config = lib.mkMerge [
    (lib.mkIf (cfg.worker.enable || cfg.broker.enable) {
      services.borgmatic.settings.commands = [
        {
          before = "action";
          when = [ "create" ];
          run = [ "${backup}/bin/openhands-backup" ];
        }
      ];
      shulker.system.modules.backup.dirs = [ "/var/lib/openhands-backups" ];
      environment.persistence = lib.mkIf config.shulker.system.modules.impermanence.enable {
        "/nix/persist".directories = [
          {
            directory = "/var/lib/openhands-backups";
            mode = "0700";
          }
        ];
      };
    })
    (lib.mkIf cfg.worker.enable {
      assertions = [
        {
          assertion = config.networking.hostName == "enderdragon";
          message = "OpenHands worker belongs on Enderdragon.";
        }
        {
          assertion = cfg.worker.secretReference != "";
          message = "OpenHands requires dedicated worker secrets.";
        }
      ];
      shulker.system.modules.containers.enable = true;
      users.groups.openhands-worker.gid = 10011;
      users.users.openhands-worker = {
        isSystemUser = true;
        uid = 10011;
        group = "openhands-worker";
        home = "/var/lib/openhands/home";
      };
      users.users.conquerix.extraGroups = [ "openhands-worker" ];
      # The human editor and worker own files under different UIDs. Trust only
      # this shared project, including both paths used by Git worktree metadata.
      home-manager.users.conquerix.programs.git = {
        enable = true;
        settings.safe.directory = [
          "/srv/openhands/projects/shulker/*"
          "/projects/shulker/*"
        ];
      };
      # Git worktree metadata contains absolute container paths; the host must resolve them too.
      systemd.tmpfiles.rules = [
        "d /projects 0755 root root -"
        "L /projects/shulker - - - - /srv/openhands/projects/shulker"
      ];
      services.onepassword-secrets.secrets.openhandsWorkerEnv = {
        reference = cfg.worker.secretReference;
        owner = "root";
        group = "root";
        mode = "0400";
        services = [ "openhands-worker-state" ];
      };
      systemd.services.openhands-worker-state = {
        requires = [ "opnix-secrets.service" ];
        after = [ "opnix-secrets.service" ];
        unitConfig.RequiresMountsFor = [
          "/var/lib/openhands"
          "/srv/openhands/projects/shulker"
        ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          UMask = "0077";
          EnvironmentFile = config.services.onepassword-secrets.secrets.openhandsWorkerEnv.path;
        };
        path = [
          pkgs.coreutils
          pkgs.findutils
          pkgs.acl
          pkgs.util-linux
          pkgs.bash
          pkgs.python3
        ];
        script = ''
          install -d -m 0700 -o openhands-worker -g openhands-worker /var/lib/openhands /var/lib/openhands/home /var/lib/openhands/settings /var/lib/openhands/cache /var/lib/openhands/conversations /var/lib/openhands/bash-events
          install -d -m 2770 -o openhands-worker -g openhands-worker /srv/openhands/projects/shulker /srv/openhands/projects/shulker/worktrees
          runuser -u openhands-worker -- python ${./seed-native.py} /var/lib/openhands/settings ${./native-profile.json}
          bash ${./prepare-project.sh} /srv/openhands/projects/shulker 10011
          install -d -m 0750 -o root -g openhands-worker /run/openhands
          python ${./render-config.py} ${workerPolicy} /run/openhands/config.json
          chown openhands-worker:openhands-worker /run/openhands/config.json
          chmod 0400 /run/openhands/config.json
        '';
      };
      virtualisation.oci-containers.containers.openhands-worker = {
        image = images.worker;
        pull = "missing";
        user = "10011:10011";
        cmd = [
          "--host"
          "0.0.0.0"
          "--port"
          "8000"
        ];
        ports = [ "127.0.0.1:23249:8000" ];
        environment = {
          HOME = "/state/home";
          OH_PERSISTENCE_DIR = "/state/settings";
          OPENHANDS_AGENT_SERVER_CONFIG_PATH = "/run/openhands/config.json";
          OH_ENABLE_VSCODE = "false";
          OH_ENABLE_BROWSER = "false";
          DO_NOT_TRACK = "1";
          OH_TELEMETRY_CONSENT = "denied";
        };
        volumes = [
          "/var/lib/openhands:/state:rw"
          "/srv/openhands/projects/shulker:/projects/shulker:rw"
          "/run/openhands/config.json:/run/openhands/config.json:ro"
        ];
        extraOptions = [
          "--read-only"
          "--cap-drop=ALL"
          "--security-opt=no-new-privileges:true"
          # The pinned PyInstaller binary extracts executable libraries to scratch.
          "--tmpfs=/tmp:rw,exec,nosuid,nodev,size=512m"
          "--memory=4g"
          "--cpus=2"
          "--pids-limit=512"
          # Host Docker defaults to journald; these rotation options require json-file.
          "--log-driver=json-file"
          "--log-opt=max-size=10m"
          "--log-opt=max-file=3"
        ];
      };
      systemd.services.docker-openhands-worker = {
        requires = [ "openhands-worker-state.service" ];
        after = [ "openhands-worker-state.service" ];
        unitConfig.RequiresMountsFor = [
          "/var/lib/openhands"
          "/srv/openhands/projects/shulker"
        ];
      };
      environment.persistence = lib.mkIf config.shulker.system.modules.impermanence.enable {
        "/nix/persist".directories = [
          {
            directory = "/var/lib/openhands";
            user = "openhands-worker";
            group = "openhands-worker";
            mode = "0700";
          }
          {
            directory = "/srv/openhands/projects/shulker";
            user = "openhands-worker";
            group = "openhands-worker";
            mode = "2770";
          }
        ];
      };
    })
    (lib.mkIf cfg.frontend.enable {
      shulker.system.modules.openhands.frontend.configFile = caddyfile;
      shulker.system.modules.openhands.frontend.configText = caddyText;
      assertions = [
        {
          assertion = config.networking.hostName == "shulker";
          message = "OpenHands frontend belongs on Shulker.";
        }
      ];
      systemd.services.openhands-canvas = {
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          ExecStart = "${pkgs.caddy}/bin/caddy run --adapter caddyfile --config ${caddyfile}";
          DynamicUser = true;
          StateDirectory = "openhands-canvas";
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          Restart = "on-failure";
        };
      };
    })
    (lib.mkIf cfg.broker.enable {
      assertions = [
        {
          assertion =
            config.networking.hostName == "shulker" && config.shulker.system.modules.hermes-trial.enable;
          message = "OpenHands broker requires Shulker's isolated Overseer.";
        }
        {
          assertion = cfg.broker.agentProfileId == nativeProfile.id && cfg.broker.secretReference != "";
          message = "OpenHands broker requires the native coding profile and a dedicated backend key.";
        }
      ];
      users.groups.openhands-broker.gid = 10012;
      users.users.openhands-broker = {
        isSystemUser = true;
        uid = 10012;
        group = "openhands-broker";
      };
      services.onepassword-secrets.secrets.openhandsBrokerKey = {
        reference = cfg.broker.secretReference;
        owner = "root";
        group = "root";
        mode = "0400";
        services = [ "openhands-broker" ];
      };
      systemd.services.openhands-broker = {
        wantedBy = [ "multi-user.target" ];
        requires = [ "opnix-secrets.service" ];
        after = [ "opnix-secrets.service" ];
        environment.PYTHONPATH = toString ./.;
        serviceConfig = {
          ExecStart = "${python}/bin/python -m broker.server ${policy}";
          User = "openhands-broker";
          Group = "hermes-overseer";
          UMask = "0077";
          RuntimeDirectory = "openhands-broker";
          RuntimeDirectoryMode = "0750";
          RuntimeDirectoryPreserve = "yes";
          StateDirectory = "openhands-broker";
          StateDirectoryMode = "0700";
          LoadCredential = "backend-key:${config.services.onepassword-secrets.secrets.openhandsBrokerKey.path}";
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          RestrictAddressFamilies = [
            "AF_UNIX"
            "AF_INET"
            "AF_INET6"
          ];
          CapabilityBoundingSet = "";
          MemoryMax = "128M";
          TasksMax = 32;
          Restart = "on-failure";
        };
      };
      environment.persistence = lib.mkIf config.shulker.system.modules.impermanence.enable {
        "/nix/persist".directories = [
          {
            directory = "/var/lib/openhands-broker";
            user = "openhands-broker";
            group = "hermes-overseer";
            mode = "0700";
          }
        ];
      };
    })
  ];
}
