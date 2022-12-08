{ pkgs ? import <nixpkgs> { } }:
let
  options = [
    ''--option experimental-features "nix-command flakes"''
  ];
in
pkgs.mkShell {
  name = "shulker";
  nativeBuildInputs = with pkgs; [
    git
    git-crypt
    nixUnstable
  ];

  shellHook = ''
      PATH=${pkgs.writeShellScriptBin "nix" ''
      ${pkgs.nixVersions.stable}/bin/nix ${builtins.concatStringsSep " " options} "$@"
    ''}/bin:$PATH
  '';
}
