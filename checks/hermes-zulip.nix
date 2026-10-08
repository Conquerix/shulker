# Enabled host placement and explicit disabled fixtures enforce the trial boundary.
{ self, pkgs, ... }:
let
  production = self.nixosConfigurations.shulker.config;
  disabled =
    (self.nixosConfigurations.shulker.extendModules {
      modules = [
        (
          { lib, ... }:
          {
            shulker.system.modules.zulip.enable = lib.mkForce false;
            shulker.system.modules.hermes-trial.enable = lib.mkForce false;
            shulker.system.modules.openhands.broker.enable = lib.mkForce false;
          }
        )
      ];
    }).config;
  fixture =
    (self.nixosConfigurations.shulker.extendModules {
      modules = [
        (
          { lib, ... }:
          {
            shulker.system.modules.openhands.broker.enable = lib.mkForce false;
            shulker.system.modules.hermes-trial = {
              enable = lib.mkForce true;
              model = lib.mkForce "fixture-model-from-authenticated-catalog";
              allowedUsers = lib.mkForce [ 123 ];
              allowedChannels = lib.mkForce [ 42 ];
              secretReference = lib.mkForce "op://Fixture/Overseer/Environment";
            };
            shulker.system.modules.zulip = {
              enable = lib.mkForce true;
              publicUrl = lib.mkForce "https://chat.example.test";
              administratorEmail = lib.mkForce "owner@example.test";
              oidcIssuer = lib.mkForce "https://sso.example.test";
              oidcClientId = lib.mkForce "fixture";
              trustedProxyAddresses = lib.mkForce [ "172.30.0.1" ];
              secretReference = lib.mkForce "op://Fixture/Zulip/Secrets";
            };
          }
        )
      ];
    }).config;
  overseer = fixture.virtualisation.oci-containers.containers.hermes-overseer;
  trialConfig =
    (pkgs.formats.yaml { }).generate "overseer-contract-config.yaml"
      fixture.shulker.system.modules.hermes-trial.runtimeConfig;
  zulip = fixture.shulker.system.modules.zulip.composeConfig;
  source = import ../system/modules/nixos/services/hermes-trial/package.nix { inherit pkgs; };
  python = pkgs.python3.withPackages (p: [
    p.pytest
    p.pytest-asyncio
    p.httpx
    p.python-dotenv
    p.pyyaml
    p.platformdirs
    p.rich
  ]);
in
{
  hermes-zulip-contract =
    assert production.virtualisation.oci-containers.containers ? hermes-overseer;
    assert !(disabled.virtualisation.oci-containers.containers ? hermes-overseer);
    assert !(disabled.services.onepassword-secrets.secrets ? hermesOverseerEnv);
    assert production.systemd.services ? zulip-trial;
    assert
      production.shulker.system.modules.zulip.composeConfig.services.zulip.ports
      == [ "127.0.0.1:23248:80" ];
    assert !(disabled.systemd.services ? zulip-trial);
    assert !(disabled.services.onepassword-secrets.secrets ? zulipTrialSecrets);
    assert overseer.user == "10010:10010";
    assert builtins.elem "zulip-trial.service" fixture.systemd.services.docker-hermes-overseer.after;
    assert builtins.elem "newt.service" fixture.systemd.services.docker-hermes-overseer.after;
    assert pkgs.lib.hasInfix "/api/v1/server_settings"
      fixture.systemd.services.docker-hermes-overseer.preStart;
    assert builtins.elem "--read-only" overseer.extraOptions;
    assert builtins.elem "--init" overseer.extraOptions;
    assert builtins.elem "--log-driver=json-file" overseer.extraOptions;
    assert builtins.elem "--cap-drop=ALL" overseer.extraOptions;
    assert builtins.all (
      v: !(pkgs.lib.hasPrefix "/var/lib/hermes:" v) && !(pkgs.lib.hasInfix "docker.sock" v)
    ) overseer.volumes;
    assert zulip.services.zulip.ports == [ "127.0.0.1:23248:80" ];
    assert !(zulip.services.database ? ports);
    assert zulip.networks.private.internal;
    assert builtins.all (image: pkgs.lib.hasInfix "@sha256:" image) (
      builtins.attrValues fixture.shulker.system.modules.zulip.images
    );
    pkgs.runCommand "hermes-zulip-contract" { nativeBuildInputs = [ python ]; } ''
      python - ${pkgs.lib.escapeShellArg trialConfig} <<'PY'
      import sys, yaml
      with open(sys.argv[1]) as handle:
          config = yaml.safe_load(handle)
      assert config["model"]["provider"] == "openai-codex"
      assert config["model"]["default"] == "fixture-model-from-authenticated-catalog"
      assert not config.get("fallback_model")
      PY
      touch "$out"
    '';
  hermes-zulip-tests =
    pkgs.runCommand "hermes-zulip-tests"
      {
        nativeBuildInputs = [
          python
          pkgs.bash
          pkgs.util-linux
          pkgs.gnutar
          pkgs.gzip
        ];
      }
      ''
            export HOME="$TMPDIR/home" HERMES_HOME="$TMPDIR/hermes" HERMES_TEST_SOURCE=${source}
            mkdir -p "$HOME" "$HERMES_HOME"
            mkdir -p repo/tests repo/system/modules/nixos/services/hermes-trial
        cp -R ${../tests/hermes-zulip} repo/tests/hermes-zulip
        cp -R ${../system/modules/nixos/services/hermes-trial/plugin} repo/system/modules/nixos/services/hermes-trial/plugin
        cd repo
            python -m pytest -q -p no:cacheprovider tests/hermes-zulip
            python ${../tests/zulip-config.py} ${../system/modules/nixos/services/zulip/render-config.py}
            bash ${../tests/zulip-backup.sh} ${../system/modules/nixos/services/zulip/backup.sh}
            touch "$out"
      '';
}
