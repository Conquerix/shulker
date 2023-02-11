{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.modules.dev.python;
  configHome = config.xdg.configHome;
  dataHome = config.xdg.dataHome;

  extraPackages = p: with p; [
    pip
    pysmt
    z3
    setuptools
    numpy
    matplotlib
    jupytext
    jupyter
    scipy
    (
      buildPythonPackage rec {
        pname = "profilehooks";
        version = "1.12.0";
        src = fetchPypi {
          inherit pname version;
          sha256 = "sha256-Bbh1id+KjGMP1wG65gCMwc//RFe9AGSIetJSSDJ6W6M=";
        };
        doCheck = false;
      }
    )
  ];
  
in
{
  options.shulker.modules.dev.python = {
    enable = mkEnableOption "python configuration";
  };

  config = mkIf cfg.enable {
    home.packages = with pkgs; [
      (python310.withPackages extraPackages)
      pipenv
      z3
    ];

    # home.sessionVariables = {
    #  PIP_CONFIG_FILE = "${configHome}/pip/pip.conf";
    #  PIP_LOG_FILE = "${dataHome}/pip/log";
    #  PYLINTHOME = "${dataHome}/pylint";
    #  PYLINTRC = "${configHome}/pylint/pylintrc";
    #  PYTHONSTARTUP = "${configHome}/python/pythonrc";
    # };
  };
}
