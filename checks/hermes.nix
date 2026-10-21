# Runtime credential/bootstrap regressions and evaluated shared-instance isolation.
{ pkgs, self, ... }:
let
  inherit (pkgs) lib;
  config = self.nixosConfigurations.shulker.config;
  cfg = config.shulker.system.modules.hermes-agent;
  render = import ../system/modules/nixos/services/hermes-agent/render-instance.nix {
    inherit lib pkgs config;
  };
  engineer = config.virtualisation.oci-containers.containers.hermes-engineer;
  overseer = config.virtualisation.oci-containers.containers.hermes;
  # Render a third instance from the same implementation, with all capabilities off.
  worker = render "worker" (
    cfg.instances.engineer
    // {
      containerName = "hermes-worker";
      stateDir = "/var/lib/hermes-worker";
      credentials = { };
      discord = {
        enable = false;
        allowedUsers = [ ];
      };
    }
  );
  collision = render "agent" (
    cfg.instances.engineer
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
      serviceAccount = {
        enable = true;
        reference = "op://fixture/token";
      };
    }
  );
  has = lib.hasInfix;
  safeVolumes =
    container:
    builtins.length container.volumes == 3
    && lib.all (
      v: !(has "overseer" v) && !(has "docker.sock" v) && !(has "host-key" v)
    ) container.volumes;
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
    assert builtins.length collision.secretNames == 4;
    assert builtins.length (lib.unique collision.secretNames) == 2;
    assert cfg.instances.overseer.containerName == "hermes";
    assert cfg.instances.overseer.stateDir == "/var/lib/hermes-clean";
    assert cfg.instances.engineer.stateDir == "/var/lib/hermes-engineer";
    assert engineer.image == overseer.image;
    assert engineer.ports == [ ];
    assert overseer.ports == [ "127.0.0.1:23234:9119" ];
    assert safeVolumes engineer && safeVolumes worker.container;
    assert worker.container.ports == [ ];
    assert worker.secrets == { };
    assert
      !(cfg.instances.engineer.hostAdministration.enable || cfg.instances.engineer.serviceAccount.enable);
    assert builtins.hasAttr "hermesOverseerDashboard" config.services.onepassword-secrets.secrets;
    assert builtins.hasAttr "hermesEngineerDiscord" config.services.onepassword-secrets.secrets;
    assert lib.all
      (
        name:
        let
          i = cfg.instances.${name};
          service = config.systemd.services."docker-${i.containerName}";
        in
        builtins.elem "opnix-secrets.service" service.after
        && builtins.elem "opnix-secrets.service" service.requires
        && has "render-credentials.py" service.preStart
        && !(has "op read" service.preStart)
        && builtins.elem i.stateDir config.shulker.system.modules.backup.dirs
        && lib.any (d: d.directory == i.stateDir) config.environment.persistence."/nix/persist".directories
      )
      [
        "overseer"
        "engineer"
      ];
    assert lib.all
      (
        label:
        config.services.onepassword-secrets.secrets."hermesEngineer${
          lib.toUpper (builtins.substring 0 1 label)
        }${builtins.substring 1 (-1) label}".services == [ "docker-hermes-engineer" ]
      )
      [
        "discord"
        "provider"
      ];
    assert builtins.length worker.tmpfiles == 3;
    assert worker.persistence.directory == "/var/lib/hermes-worker";
    pkgs.runCommand "hermes-instances-contract" { } ''touch "$out"'';
}
