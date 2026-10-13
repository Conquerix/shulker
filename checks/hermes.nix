# Exercise private, complete credential refresh without accessing a real vault.
{ pkgs, ... }:
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
        touch "$out"
      '';
}
