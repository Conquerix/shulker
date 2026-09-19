{
  pkgs,
  wardenConfig,
  self,
  system,
  ...
}:
let
  cfg = wardenConfig.shulker.system.modules.actual-budget;
in
{
  actual-budget-contract =
    assert cfg.enable;
    assert cfg.port == 23246;
    assert cfg.composeConfig.services.server.ports == [ "127.0.0.1:23246:5006/tcp" ];
    assert cfg.composeConfig.services.server.environment.ACTUAL_OPENID_ENFORCE == "true";
    assert cfg.composeConfig.services.server.environment.ACTUAL_USER_CREATION_MODE == "manual";
    assert cfg.composeConfig.services.server.restart == "on-failure:5";
    assert wardenConfig.services.onepassword-secrets.secrets.actualBudgetEnv.mode == "0400";
    assert builtins.elem "${cfg.stateDir}/.zfs/snapshot/borgmatic/data"
      wardenConfig.shulker.system.modules.backup.dirs;
    pkgs.runCommand "actual-budget-contract"
      {
        nativeBuildInputs = [
          pkgs.python3
          pkgs.bash
        ];
      }
      ''
        python3 ${../tests/actual-budget-runtime.py} ${../system/modules/nixos/services/actual-budget/runtime.sh}
        touch "$out"
      '';
  actual-budget-state-contract =
    pkgs.runCommand "actual-budget-state-contract"
      {
        nativeBuildInputs = [
          pkgs.bash
          pkgs.coreutils
        ];
      }
      ''
        sed -e 's|flash_pool/flash/storage/taskview|flash_pool/flash/storage/actual-budget|g' -e 's/21474836480/10737418240/g' ${../tests/taskview-state.sh} >fixture.sh
        bash fixture.sh ${pkgs.writeText "actual-budget-state.sh" cfg.validateStateScript}
        touch "$out"
      '';
  actual-budget-docs-contract = pkgs.runCommand "actual-budget-docs-contract" { } ''
    grep -q 'budget.shulker.link' ${self.packages.${system}.host-docs-warden}/warden.md
    test -f ${self.packages.${system}.wiki-docs}/Service-Actual-Budget.md
    touch "$out"
  '';
}
