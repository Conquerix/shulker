# Administrator-only deployment and synthetic unprivileged renderer contracts.
{ pkgs, self, ... }:
let
  inherit (pkgs) lib;
  config = self.nixosConfigurations.shulker.config;
  cfg = config.shulker.system.modules.hermes-agent;
  admin = cfg.instances.administrator;
  container = config.virtualisation.oci-containers.containers.hermes-administrator;
  render = import ../system/modules/nixos/services/hermes-agent/render-instance.nix {
    inherit lib pkgs config;
  };
  worker = render "worker" (
    admin
    // {
      containerName = "hermes-worker";
      stateDir = "/var/lib/hermes-worker";
      credentials = { };
      omh.enable = false;
      discord = {
        enable = false;
        allowedUsers = [ ];
      };
      serviceAccount = {
        enable = false;
        reference = null;
      };
      hostAdministration = admin.hostAdministration // {
        enable = false;
      };
    }
  );
  collision = render "agent" (
    admin
    // {
      credentials = {
        a-b = {
          reference = "op://fixture/a";
          requiredKeys = [ "A" ];
        };
        a--b = {
          reference = "op://fixture/b";
          requiredKeys = [ "B" ];
        };
        service--account = {
          reference = "op://fixture/c";
          requiredKeys = [ "C" ];
        };
      };
    }
  );
  retired = [
    "hermes"
    "hermes-engineer"
    "hermes-artificer"
    "hermes-quartermaster"
    "openbot-trial"
    "garcon"
    "paperclip-airgap"
    "paperclip-airgap-db"
    "tuxee-hq-trial"
    "quartz-build"
    "quartz-web"
  ];
in
{
  hermes-credentials-contract =
    pkgs.runCommand "hermes-credentials-contract"
      {
        nativeBuildInputs = [
          pkgs.python3
          pkgs.openssh
        ];
      }
      ''
        python3 ${../tests/hermes-credentials.py} ${../system/modules/nixos/services/hermes-agent/render-credentials.py}
        python3 ${../tests/hermes-bootstrap.py} ${../system/modules/nixos/services/hermes-agent/bootstrap.py}
        touch "$out"
      '';
  hermes-instances-contract =
    assert builtins.attrNames cfg.instances == [ "administrator" ];
    assert admin.stateDir == "/var/lib/hermes-administrator";
    assert admin.hostAdministration.enable && admin.serviceAccount.enable && admin.omh.enable;
    assert admin.hostAdministration.user == "hermes-administrator-operator";
    assert admin.discord.allowedUsers == [ "240780407442767873" ];
    assert container.ports == [ ];
    assert container.environment.DISCORD_ALLOW_ALL_USERS == "false";
    assert container.environment.DISCORD_REQUIRE_MENTION == "true";
    assert container.environment.DISCORD_ALLOW_BOTS == "none";
    assert lib.all (v: !(lib.hasInfix "docker.sock" v)) container.volumes;
    assert lib.all (
      name: !(builtins.hasAttr name config.virtualisation.oci-containers.containers)
    ) retired;
    assert !(config.users.users ? hermes-operator);
    assert config.shulker.system.modules.omniroute.enable;
    assert builtins.hasAttr "hermesAdministratorDiscord" config.services.onepassword-secrets.secrets;
    assert !(builtins.hasAttr "hermesOverseerHostKey" config.services.onepassword-secrets.secrets);
    assert builtins.elem admin.stateDir config.shulker.system.modules.backup.dirs;
    assert lib.any (
      d: d.directory == admin.stateDir
    ) config.environment.persistence."/nix/persist".directories;
    assert worker.container.ports == [ ];
    assert builtins.length worker.container.volumes == 3;
    assert worker.secrets == { };
    assert builtins.length worker.tmpfiles == 3;
    assert worker.persistence.directory == "/var/lib/hermes-worker";
    assert builtins.length collision.secretNames == 5;
    assert builtins.length (lib.unique collision.secretNames) == 3;
    pkgs.runCommand "hermes-instances-contract" { } ''touch "$out"'';
}
