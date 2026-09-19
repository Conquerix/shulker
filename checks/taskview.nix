# Contracts for TaskView's storage and runtime boundary.
{
  self,
  system,
  pkgs,
  wardenConfig,
  ...
}:
let
  cfg = wardenConfig.shulker.system.modules.taskview;
in
{
  taskview-core-contract =
    assert cfg.enable;
    assert cfg.stateDir == "/storage/flash/taskview";
    assert cfg.dataset == "flash_pool/flash/storage/taskview";
    assert cfg.datasetQuotaBytes == 21474836480;
    assert cfg.apiPort == 23243;
    assert wardenConfig.fileSystems.${cfg.stateDir}.fsType == "zfs";
    pkgs.runCommand "taskview-core-contract" { } ''touch "$out"'';
  taskview-state-contract =
    pkgs.runCommand "taskview-state-contract"
      {
        nativeBuildInputs = [
          pkgs.bash
          pkgs.coreutils
        ];
      }
      ''
        bash ${../tests/taskview-state.sh} ${pkgs.writeText "taskview-state.sh" cfg.validateStateScript}
        touch "$out"
      '';
  taskview-runtime-contract =
    pkgs.runCommand "taskview-runtime-contract"
      {
        nativeBuildInputs = [
          pkgs.bash
          pkgs.coreutils
          pkgs.util-linux
          pkgs.python3
          pkgs.gnugrep
          pkgs.findutils
          pkgs.jq
        ];
      }
      ''
        python3 ${../tests/taskview-config.py} ${../system/modules/nixos/services/taskview/render-config.py}
        bash ${../tests/taskview-runtime.sh} ${../system/modules/nixos/services/taskview/lifecycle.sh}
        bash ${../tests/taskview-backup.sh} ${../system/modules/nixos/services/taskview/backup.sh}
        touch "$out"
      '';
  taskview-stack-contract =
    assert builtins.length (builtins.attrNames cfg.composeConfig.services) == 6;
    assert cfg.composeConfig.services.api.ports == [ "127.0.0.1:23243:1401/tcp" ];
    assert cfg.composeConfig.services.centrifugo.ports == [ "127.0.0.1:23245:8000/tcp" ];
    assert !(cfg.composeConfig.services.database ? ports);
    assert cfg.composeConfig.networks.private.internal;
    assert cfg.composeConfig.services.database.restart == "on-failure:5";
    assert cfg.composeConfig.services.database.networks == [ "private" ];
    assert cfg.composeConfig.services.api.environment.ALLOW_PUBLIC_REGISTRATION == "false";
    assert cfg.composeConfig.services.api.environment.CENTRIFUGO_API_URL == "http://centrifugo:9000";
    assert cfg.centrifugoConfig.http_server.internal_port == "9000";
    assert (builtins.head cfg.centrifugoConfig.channel.namespaces).allow_user_limited_channels;
    assert !(cfg.composeConfig.services.mcp ? env_file);
    assert builtins.elem "${cfg.stateDir}/backups" wardenConfig.shulker.system.modules.backup.dirs;
    pkgs.runCommand "taskview-stack-contract" { } ''touch "$out"'';

  taskview-docs-contract = pkgs.runCommand "taskview-docs-contract" { } ''
    grep -q 'TaskView' ${self.packages.${system}.host-docs-warden}/warden.md
    for host in tasks tasks-api tasks-mcp tasks-events; do
      grep -q "$host.shulker.link" ${self.packages.${system}.host-docs-warden}/warden.md
    done
    test -f ${self.packages.${system}.wiki-docs}/Service-TaskView.md
    touch "$out"
  '';

}
