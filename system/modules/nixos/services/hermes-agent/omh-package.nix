# Build a real wheel so upstream records package_site for native plugin imports.
# Copy only pure Python/data into a mount; use the image's interpreter at runtime.
{ pkgs }:
let
  revision = "cc061e29a1b65e621c9dde1180e53a0c77970f8b";
  package = pkgs.python3Packages.buildPythonPackage {
    pname = "oh-my-hermes";
    version = "4.0.6";
    pyproject = true;
    src = pkgs.fetchurl {
      name = "oh-my-hermes-${revision}.tar.gz";
      url = "https://codeload.github.com/rlaope/oh-my-hermes/tar.gz/${revision}";
      hash = "sha256-U7lihIXTuG53pUuQKYDBNCfE7cneKXAHoskPgNOlB4Y=";
    };
    build-system = [ pkgs.python3Packages.setuptools ];
    doCheck = false;
    pythonImportsCheck = [ "omh.cli" ];
    meta.license = pkgs.lib.licenses.mit;
  };
in
pkgs.runCommand "oh-my-hermes-bundle-${builtins.substring 0 12 revision}"
  {
    nativeBuildInputs = [ pkgs.python3 ];
    passthru = { inherit revision; };
  }
  ''
    mkdir -p "$out/lib"
    cp -r ${package}/${pkgs.python3.sitePackages}/. "$out/lib/"
    chmod -R u+w "$out/lib"
    # Nix's RECORD retains the wheel's files; remove only interpreter bytecode.
    export OMH_BUNDLE_OUT="$out"
    python3 - <<'PY'
    import os, pathlib, shutil
    out = pathlib.Path(os.environ['OMH_BUNDLE_OUT'])
    for cache in out.rglob('__pycache__'):
        shutil.rmtree(cache)
    (out / 'revision').write_text('${revision}')
    (out / 'launch.py').write_text(
        'import pathlib, sys\n'
        'sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent / "lib"))\n'
        'from omh.cli import main\n'
        'raise SystemExit(main())\n'
    )
    PY
    python3 "$out/launch.py" setup --help >/dev/null
  ''
