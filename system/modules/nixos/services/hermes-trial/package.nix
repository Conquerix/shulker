# Prepare the exact inspected Hermes source with the narrow approval transport fix.
{ pkgs }:
let
  upstream = import ./upstream.nix;
  archive = pkgs.fetchurl {
    url = "https://codeload.github.com/NousResearch/hermes-agent/tar.gz/${upstream.revision}";
    inherit (upstream) hash;
  };
in
pkgs.runCommand "hermes-overseer-source"
  {
    nativeBuildInputs = [
      pkgs.gnutar
      pkgs.gzip
      pkgs.patch
    ];
  }
  ''
    mkdir -p "$out"
    tar -xzf ${archive} -C "$out" --strip-components=1
    cd "$out"
    patch -p1 < ${./approval-request-id.patch}
  ''
