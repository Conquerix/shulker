{ ... }:

_final: prev:

let
  sha256 = "sha256-t6n4uID7KTu/BqsmndJOft0ifxZNfv9lfqlzFX0ApKw=";
  version = "0.2.0";
in
{
  # https://github.com/NixOS/nixpkgs/issues/86349
  vhs = (prev.callPackage "${prev.path}/pkgs/applications/misc/vhs" {
    buildGoModule = args: prev.buildGoModule (args // {
      version = version;
      src = prev.fetchFromGitHub {
        owner = "charmbracelet";
        repo = "vhs";
        rev = "v${version}";
        sha256 = "sha256-t6n4uID7KTu/BqsmndJOft0ifxZNfv9lfqlzFX0ApKw=";
      };

      vendorHash = "sha256-9nkRr5Jh1nbI+XXbPj9KB0ZbLybv5JUVovpB311fO38=";
    });
  });
}
