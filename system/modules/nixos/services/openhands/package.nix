# The browser assets are the only Canvas image content installed on Shulker.
{ pkgs }:
let
  assets =
    pkgs.runCommand "openhands-canvas-assets-1.25.0"
      {
        nativeBuildInputs = [
          pkgs.python3
          pkgs.cacert
        ];
        SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
        outputHashMode = "recursive";
        outputHashAlgo = "sha256";
        outputHash = "sha256-b4/dzNQGT77paG0e6bOSOId+GS4N6QKMy4nfjhIEc80=";
      }
      ''
        python ${./fetch-assets.py} "$out"
      '';
in
{
  frontend =
    pkgs.runCommand "openhands-canvas-private-1.25.0" { nativeBuildInputs = [ pkgs.python3 ]; }
      ''
        cp -R ${assets} "$out"
        chmod -R u+w "$out"
        echo 'window.__AGENT_CANVAS_DO_NOT_TRACK__ = true;' > "$out/privacy.js"
        substituteInPlace "$out/index.html" --replace-fail '<head>' '<head><script src="/canvas/privacy.js"></script>'
        python ${./script-policy.py} "$out"
      '';
  sdkSource =
    let
      archive = pkgs.fetchurl {
        url = "https://codeload.github.com/OpenHands/software-agent-sdk/tar.gz/refs/tags/v1.53.0";
        hash = "sha256-RVX+sE/3N5Lk1zkEhvGsRWCdUdUmbjsgjiyBWKcgh+s=";
      };
    in
    pkgs.runCommand "openhands-sdk-source-1.53.0"
      {
        nativeBuildInputs = [
          pkgs.gnutar
          pkgs.gzip
        ];
      }
      ''
        mkdir -p "$out"
        tar -xzf ${archive} -C "$out" --strip-components=1
      '';
}
