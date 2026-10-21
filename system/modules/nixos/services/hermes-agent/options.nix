{ config, lib, ... }:
let
  cfg = config.shulker.system.modules.hermes-agent;
  inherit (lib) mkOption mkEnableOption types;
  reference = types.strMatching "op://.+";
  safeName = types.strMatching "[a-z][a-z0-9-]*";
  source = types.submodule {
    options = {
      reference = mkOption { type = reference; };
      requiredKeys = mkOption {
        type = types.listOf (types.strMatching "[A-Z][A-Z0-9_]*");
        description = "Exact nonempty key set permitted in this source (not a minimum set).";
      };
    };
  };
in
{
  options.shulker.system.modules.hermes-agent = {
    enable = mkEnableOption "named Hermes instances";
    impermanence = mkEnableOption "persistent Hermes instance state";
    instances = mkOption {
      default = { };
      type = types.attrsOf (
        types.submodule (
          { name, ... }: {
            options = {
              enable = mkOption {
                type = types.bool;
                default = true;
              };
              containerName = mkOption {
                type = safeName;
                default = "hermes-${name}";
              };
              stateDir = mkOption {
                type = types.strMatching "/[A-Za-z0-9/_-]+";
                default = "/var/lib/hermes-${name}";
              };
              image = mkOption {
                type = types.str;
                default = "docker.io/nousresearch/hermes-agent:stable@sha256:9774f4f39a9bb8c2f68ce728ed5e99ddbad282163be56764afacf88ed952b784";
              };
              dashboard = {
                enable = mkEnableOption "private dashboard and local API";
                port = mkOption {
                  type = types.port;
                  default = 23234;
                };
                publicUrl = mkOption {
                  type = types.str;
                  default = "";
                };
              };
              omniroute.enable = mkOption {
                type = types.bool;
                default = config.shulker.system.modules.omniroute.enable;
              };
              discord = {
                enable = mkEnableOption "native Discord messaging";
                allowedUsers = mkOption {
                  type = types.listOf (types.strMatching "[0-9]+");
                  default = [ ];
                };
              };
              credentials = mkOption {
                type = types.attrsOf source;
                default = { };
                description = "Instance-scoped OpNix environment sources; labels and references are case-sensitive.";
              };
              serviceAccount = {
                enable = mkEnableOption "1Password CLI capability (independent of startup credentials and host administration)";
                reference = mkOption {
                  type = types.nullOr reference;
                  default = null;
                };
              };
              hostAdministration = {
                enable = mkEnableOption "dedicated SSH identity with unrestricted root sudo";
                user = mkOption {
                  type = safeName;
                  default = "hermes-${name}-operator";
                };
                sshPublicKey = mkOption {
                  type = types.str;
                  default = "";
                };
                hostPublicKey = mkOption {
                  type = types.str;
                  default = "";
                };
                privateKeyReference = mkOption {
                  type = types.nullOr reference;
                  default = null;
                };
              };
              initial = {
                files = mkOption {
                  type = types.attrsOf types.path;
                  default = { };
                  description = "Non-secret initial files relative to stateDir (data/ or workspace/); existing files and symlinks are never replaced.";
                };
                settings = mkOption {
                  type = types.attrsOf types.str;
                  default = { };
                  description = "Non-secret dotted Hermes config keys, applied via native config set only when config.yaml is absent.";
                };
                plugins = mkOption {
                  type = types.listOf safeName;
                  default = [ ];
                  description = "Native plugins enable commands for fresh config only; never reconcile learned plugin state.";
                };
              };
            };
          }
        )
      );
    };
  };
  config.assertions = lib.mkIf cfg.enable [
    {
      assertion = cfg.instances != { };
      message = "Hermes requires at least one named instance.";
    }
  ];
}
