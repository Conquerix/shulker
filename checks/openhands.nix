# Enabled production placement plus explicit disabled and isolated synthetic fixtures.
{ self, pkgs, ... }:
let
  shulker = self.nixosConfigurations.shulker.config;
  enderdragon = self.nixosConfigurations.enderdragon.config;
  disabledHost =
    host:
    (self.nixosConfigurations.${host}.extendModules {
      modules = [
        (
          { lib, ... }:
          {
            shulker.system.modules.openhands = {
              frontend.enable = lib.mkForce false;
              broker.enable = lib.mkForce false;
              worker.enable = lib.mkForce false;
            };
          }
        )
      ];
    }).config;
  disabledShulker = disabledHost "shulker";
  disabledEnderdragon = disabledHost "enderdragon";
  frontend =
    (self.nixosConfigurations.shulker.extendModules {
      modules = [
        (
          { lib, ... }:
          {
            shulker.system.modules.openhands = {
              frontend.enable = lib.mkForce true;
              broker = {
                enable = lib.mkForce true;
                secretReference = lib.mkForce "op://Fixture/OpenHands/Key";
              };
            };
            shulker.system.modules.hermes-trial = {
              enable = lib.mkForce true;
              model = lib.mkForce "fixture-model";
              allowedUsers = lib.mkForce [ 123 ];
              allowedChannels = lib.mkForce [ 42 ];
              secretReference = lib.mkForce "op://Fixture/Overseer/Environment";
            };
          }
        )
      ];
    }).config;
  worker =
    (self.nixosConfigurations.enderdragon.extendModules {
      modules = [
        (
          { lib, ... }:
          {
            shulker.system.modules.openhands.worker = {
              enable = lib.mkForce true;
              secretReference = lib.mkForce "op://Fixture/OpenHands/Worker";
            };
          }
        )
      ];
    }).config;
  container = worker.virtualisation.oci-containers.containers.openhands-worker;
  overseer = frontend.virtualisation.oci-containers.containers.hermes-overseer;
  python = pkgs.python3.withPackages (p: [
    p.pytest
    p.pytest-asyncio
    p.httpx
    p.python-dotenv
    p.pyyaml
    p.platformdirs
    p.rich
  ]);
  hermesSource = import ../system/modules/nixos/services/hermes-trial/package.nix { inherit pkgs; };
  # Parse the actual host config without building its Linux assets on Darwin.
  syntaxConfig = pkgs.writeText "openhands-caddy-syntax.conf" (
    builtins.replaceStrings
      [
        "import ${
          builtins.unsafeDiscardStringContext (
            toString
              (import ../system/modules/nixos/services/openhands/package.nix {
                pkgs = self.nixosConfigurations.shulker.pkgs;
              }).frontend
          )
        }/script-hashes.caddy"
      ]
      [ "vars scriptHashes \"\"" ]
      (builtins.unsafeDiscardStringContext frontend.shulker.system.modules.openhands.frontend.configText)
  );
  packages = import ../system/modules/nixos/services/openhands/package.nix { inherit pkgs; };
in
{
  openhands-contract =
    assert enderdragon.services.dbus.implementation == "dbus";
    assert shulker.systemd.services ? openhands-canvas;
    assert shulker.systemd.services ? openhands-broker;
    assert enderdragon.virtualisation.oci-containers.containers ? openhands-worker;
    assert !(shulker.virtualisation.oci-containers.containers ? openhands-worker);
    assert !(enderdragon.systemd.services ? openhands-broker);
    assert !(disabledShulker.systemd.services ? openhands-canvas);
    assert !(disabledShulker.systemd.services ? openhands-broker);
    assert !(disabledEnderdragon.virtualisation.oci-containers.containers ? openhands-worker);
    assert !(disabledShulker.services.onepassword-secrets.secrets ? openhandsBrokerKey);
    assert !(disabledEnderdragon.services.onepassword-secrets.secrets ? openhandsWorkerEnv);
    assert frontend.systemd.services ? openhands-canvas;
    assert frontend.systemd.services ? openhands-broker;
    assert !(frontend.virtualisation.oci-containers.containers ? openhands-worker);
    assert !(worker.systemd.services ? openhands-canvas);
    assert
      worker.home-manager.users.conquerix.programs.git.settings.safe.directory == [
        "/srv/openhands/projects/shulker/*"
        "/projects/shulker/*"
      ];
    assert container.user == "10011:10011";
    assert container.ports == [ "127.0.0.1:23249:8000" ];
    assert
      container.volumes == [
        "/var/lib/openhands:/state:rw"
        "/srv/openhands/projects/shulker:/projects/shulker:rw"
        "/run/openhands/config.json:/run/openhands/config.json:ro"
      ];
    assert builtins.all (s: builtins.elem s container.extraOptions) [
      "--log-driver=json-file"
      "--tmpfs=/tmp:rw,exec,nosuid,nodev,size=512m"
      "--read-only"
      "--cap-drop=ALL"
      "--security-opt=no-new-privileges:true"
      "--memory=4g"
      "--cpus=2"
      "--pids-limit=512"
    ];
    assert builtins.elem "/run/openhands-broker:/run/openhands-broker:ro" overseer.volumes;
    assert builtins.all (
      s: !(pkgs.lib.hasInfix "openhandsBrokerKey" s) && !(pkgs.lib.hasInfix "openhandsWorkerEnv" s)
    ) overseer.environmentFiles;
    assert frontend.services.onepassword-secrets.secrets.openhandsBrokerKey.owner == "root";
    assert frontend.services.onepassword-secrets.secrets.openhandsBrokerKey.mode == "0400";
    assert builtins.all (a: a.assertion) (worker.assertions ++ frontend.assertions);
    pkgs.runCommand "openhands-contract"
      {
        nativeBuildInputs = [
          pkgs.caddy
          python
        ];
      }
      ''
        export OPENHANDS_CADDY_CONFIG=${syntaxConfig} CADDY=${pkgs.caddy}/bin/caddy PYTEST_DISABLE_PLUGIN_AUTOLOAD=1
        python -m pytest -q -p no:cacheprovider ${../tests/openhands/test_frontend.py} -k adapted_listener
        touch "$out"
      '';
  openhands-tests =
    pkgs.runCommand "openhands-tests"
      {
        nativeBuildInputs = [
          python
          pkgs.bash
          pkgs.util-linux
          pkgs.gnutar
          pkgs.gzip
        ]
        ++ pkgs.lib.optionals pkgs.stdenv.isLinux [ pkgs.acl ];
      }
      ''
            export HOME="$TMPDIR/home" HERMES_HOME="$TMPDIR/hermes"
            export HERMES_TEST_SOURCE=${hermesSource} PYTEST_DISABLE_PLUGIN_AUTOLOAD=1
            mkdir -p "$HOME" "$HERMES_HOME" repo/tests repo/system/modules/nixos/services
            cp -R ${../tests/openhands} repo/tests/openhands
            cp -R ${../system/modules/nixos/services/openhands} repo/system/modules/nixos/services/openhands
            mkdir -p repo/system/modules/nixos/services/hermes-trial
            cp -R ${../system/modules/nixos/services/hermes-trial/coding} repo/system/modules/nixos/services/hermes-trial/coding
            cd repo
            python -m pytest -q -p no:cacheprovider tests/openhands
        bash ${../tests/openhands-backup.sh} ${../system/modules/nixos/services/openhands/backup.sh}
            touch "$out"
      '';
  openhands-assets =
    pkgs.runCommand "openhands-assets-contract" { nativeBuildInputs = [ python ]; }
      ''
        test -f ${packages.frontend}/index.html
        test -f ${packages.frontend}/privacy.js
        grep -q '__AGENT_CANVAS_DO_NOT_TRACK__ = true' ${packages.frontend}/privacy.js
        grep -q '/canvas/privacy.js' ${packages.frontend}/index.html
        export OPENHANDS_FRONTEND=${packages.frontend} PYTEST_DISABLE_PLUGIN_AUTOLOAD=1
        python -m pytest -q -p no:cacheprovider ${../tests/openhands/test_frontend.py} -k "inline_scripts"
        touch "$out"
      '';
}
