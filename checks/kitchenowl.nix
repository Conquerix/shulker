{
  pkgs,
  wardenConfig,
  self,
  system,
  ...
}:
let
  cfg = wardenConfig.shulker.system.modules.kitchenowl;
in
{
  kitchenowl-contract =
    assert cfg.enable;
    assert cfg.port == 23247;
    assert cfg.composeConfig.services.server.ports == [ "127.0.0.1:23247:8080/tcp" ];
    assert cfg.composeConfig.services.server.environment.DISABLE_USERNAME_PASSWORD_LOGIN == "true";
    assert cfg.composeConfig.services.server.environment.DISABLE_ONBOARDING == "true";
    assert cfg.composeConfig.services.server.environment.OPEN_REGISTRATION == "false";
    assert cfg.composeConfig.services.server.restart == "on-failure:5";
    assert wardenConfig.services.onepassword-secrets.secrets.kitchenowlEnv.mode == "0400";
    assert builtins.elem "${cfg.stateDir}/.zfs/snapshot/borgmatic/data"
      wardenConfig.shulker.system.modules.backup.dirs;
    pkgs.runCommand "kitchenowl-contract"
      {
        nativeBuildInputs = [
          pkgs.python3
          pkgs.bash
        ];
      }
      ''
        python3 ${../tests/kitchenowl-runtime.py} ${../system/modules/nixos/services/kitchenowl/runtime.sh}
        touch "$out"
      '';
  kitchenowl-state-contract =
    pkgs.runCommand "kitchenowl-state-contract"
      {
        nativeBuildInputs = [
          pkgs.bash
          pkgs.coreutils
        ];
      }
      ''
        sed -e 's|flash_pool/flash/storage/taskview|flash_pool/flash/storage/kitchenowl|g' -e 's/21474836480/10737418240/g' ${../tests/taskview-state.sh} >fixture.sh
        bash fixture.sh ${pkgs.writeText "kitchenowl-state.sh" cfg.validateStateScript}
        touch "$out"
      '';
  kitchenowl-docs-contract = pkgs.runCommand "kitchenowl-docs-contract" { } ''
    grep -q 'kitchen.shulker.link' ${self.packages.${system}.host-docs-warden}/warden.md
    test -f ${self.packages.${system}.wiki-docs}/Service-KitchenOwl.md
    touch "$out"
  '';
}
