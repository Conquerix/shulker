{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.shulker.system.modules.hermes-agent;
  instances = lib.filterAttrs (_: i: i.enable) cfg.instances;
  values = builtins.attrValues instances;
  render = import ./render-instance.nix { inherit lib pkgs config; };
  rendered = lib.mapAttrs render instances;
  distinct = list: builtins.length list == builtins.length (lib.unique list);
  overlap = a: b: a == b || lib.hasPrefix "${a}/" b || lib.hasPrefix "${b}/" a;
  reserved = [
    "service-account"
    "host-key"
  ];
in
{
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = distinct (lib.concatMap (r: r.secretNames) (builtins.attrValues rendered));
        message = "Hermes generated OpNix secret names must be unique across all instance sources and capabilities.";
      }
      {
        assertion = distinct (map (i: i.containerName) values);
        message = "Hermes container names must be unique.";
      }
      {
        assertion =
          lib.all (a: lib.all (b: a == b || !overlap a.stateDir b.stateDir) values) values
          && distinct (map (i: i.stateDir) values);
        message = "Hermes instance state directories must not overlap.";
      }
      {
        assertion = distinct (map (i: i.dashboard.port) (builtins.filter (i: i.dashboard.enable) values));
        message = "Hermes dashboard loopback ports must be unique.";
      }
      {
        assertion = distinct (
          map (i: i.hostAdministration.user) (builtins.filter (i: i.hostAdministration.enable) values)
        );
        message = "Hermes host administration identities must be unique.";
      }
    ]
    ++ lib.concatLists (
      lib.mapAttrsToList (name: i: [
        {
          assertion =
            builtins.match "[a-z][a-z0-9-]*" name != null
            && lib.all (
              label: builtins.match "[a-z][a-z0-9-]*" label != null && !(builtins.elem label reserved)
            ) (builtins.attrNames i.credentials);
          message = "Hermes instance and source labels must be safe names; capability source labels are reserved.";
        }
        {
          assertion = !i.discord.enable || i.discord.allowedUsers != [ ];
          message = "Hermes ${name}: Discord requires an explicit user allowlist.";
        }
        {
          assertion = !i.omniroute.enable || config.shulker.system.modules.omniroute.enable;
          message = "Hermes ${name}: OmniRoute network requires the host service.";
        }
        {
          assertion = !i.serviceAccount.enable || i.serviceAccount.reference != null;
          message = "Hermes ${name}: serviceAccount requires its explicit token reference.";
        }
        {
          assertion =
            !i.hostAdministration.enable
            || (
              i.hostAdministration.privateKeyReference != null
              && lib.hasPrefix "ssh-ed25519 " i.hostAdministration.sshPublicKey
              && lib.hasPrefix "ssh-ed25519 " i.hostAdministration.hostPublicKey
            );
          message = "Hermes ${name}: hostAdministration requires private-key reference and verified public keys.";
        }
        {
          assertion =
            lib.all (source: source.requiredKeys != [ ]) (builtins.attrValues i.credentials)
            && (
              let
                keys = lib.concatMap (s: s.requiredKeys) (builtins.attrValues i.credentials);
              in
              distinct keys && !(builtins.elem "OP_SERVICE_ACCOUNT_TOKEN" keys)
            )
            && lib.all (
              key:
              !(builtins.elem key [
                "DISCORD_ALLOWED_USERS"
                "DISCORD_ALLOW_ALL_USERS"
                "DISCORD_REQUIRE_MENTION"
                "DISCORD_ALLOW_BOTS"
              ])
            ) (lib.concatMap (s: s.requiredKeys) (builtins.attrValues i.credentials));
          message = "Hermes ${name}: credential key scopes must be nonempty, disjoint, and exclude capability tokens and managed policy.";
        }
        {
          assertion =
            lib.all (key: builtins.match "[a-z][A-Za-z0-9_]*\\.[A-Za-z0-9_.]+" key != null) (
              builtins.attrNames i.initial.settings
            )
            && lib.all (
              path:
              builtins.match "(data|workspace)/[A-Za-z0-9_./-]+" path != null
              && lib.all (part: part != "" && part != "." && part != "..") (lib.splitString "/" path)
              && path != "data/config.yaml"
            ) (builtins.attrNames i.initial.files);
          message = "Hermes ${name}: initial data must use safe relative paths and non-secret dotted config keys (never a config.yaml file).";
        }
        {
          assertion =
            let
              keys = lib.concatMap (s: s.requiredKeys) (builtins.attrValues i.credentials);
            in
            (!i.discord.enable || builtins.elem "DISCORD_BOT_TOKEN" keys)
            && (!i.omniroute.enable || builtins.elem "HERMES_OMNIROUTE_API_KEY" keys)
            && (
              !i.dashboard.enable
              || lib.all (k: builtins.elem k keys) [
                "HERMES_DASHBOARD_BASIC_AUTH_USERNAME"
                "HERMES_DASHBOARD_BASIC_AUTH_PASSWORD"
                "HERMES_DASHBOARD_BASIC_AUTH_SECRET"
                "API_SERVER_KEY"
              ]
            );
          message = "Hermes ${name}: enabled integrations require their scoped credential keys.";
        }
      ]) instances
    );
    shulker.system.modules.containers.enable = true;
    users.groups.hermes.gid = 10000;
    users.users.hermes = {
      isSystemUser = true;
      uid = 10000;
      group = "hermes";
    };
    virtualisation.oci-containers.containers = lib.mapAttrs' (
      name: i: lib.nameValuePair i.containerName rendered.${name}.container
    ) instances;
    systemd.services = lib.mapAttrs' (
      name: i: lib.nameValuePair "docker-${i.containerName}" rendered.${name}.service
    ) instances;
    services.onepassword-secrets.secrets = lib.foldl' (acc: r: acc // r.secrets) { } (
      builtins.attrValues rendered
    );
    systemd.tmpfiles.rules = lib.concatMap (r: r.tmpfiles) (builtins.attrValues rendered);
    environment.persistence = lib.mkIf cfg.impermanence {
      "/nix/persist".directories = map (r: r.persistence) (builtins.attrValues rendered);
    };
    shulker.system.modules.backup.dirs = map (i: i.stateDir) values;
  };
}
