{
  self,
  system,
  pkgs,
  ...
}:
{
  seafile-contract-suite =
    pkgs.runCommand "seafile-contract-suite"
      {
        contractInputs = [
          self.checks.${system}.seafile-core-contract
          self.checks.${system}.seafile-runtime-state-machine-contract
          self.checks.${system}.seafile-secret-contract
          self.checks.${system}.seafile-stack-contract
          self.checks.${system}.seafile-identity-boundary-contract
          self.checks.${system}.seafile-restore-identity-contract
          self.checks.${system}.seafile-bootstrap-contract
          self.checks.${system}.seafile-maintenance-contract
          self.checks.${system}.seafile-backup-state-machine-contract
          self.checks.${system}.seafile-backup-contract
          self.checks.${system}.seafile-docs-contract
          self.checks.${system}.seafile-release-workflow-contract
        ];
      }
      ''
        for contract in $contractInputs; do
          test -e "$contract"
        done
        touch "$out"
      '';

  wiki-publication-contract-suite =
    pkgs.runCommand "wiki-publication-contract-suite"
      {
        contractInputs = [
          self.checks.${system}.service-module-layout-contract
          self.checks.${system}.wiki-docs-contract
          self.checks.${system}.wiki-sync-contract
          self.checks.${system}.seafile-docs-contract
          self.checks.${system}.paperless-docs-contract
          self.checks.${system}.seafile-release-workflow-contract
          self.checks.${system}.paperless-release-workflow-contract
        ];
      }
      ''
        for contract in $contractInputs; do
          test -e "$contract"
        done
        touch "$out"
      '';
}
