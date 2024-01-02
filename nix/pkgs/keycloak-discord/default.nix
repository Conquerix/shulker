{ stdenv, lib, fetchurl }:

stdenv.mkDerivation rec {
  pname = "keycloak-discord";
  version = "0.5.0";

  src = fetchurl {
    url = "https://github.com/wadahiro/keycloak-discord/releases/download/v${version}/keycloak-discord-${version}.jar";
    sha256 = "ada76f52ed9aeadd256e8e5ffc00eacbbf88fce35707bffca64d9dd41b58cd00";
  };

  dontUnpack = true;
  dontBuild = true;

  installPhase = ''
    mkdir -p "$out"
    install "$src" "$out/${pname}-${version}.jar"
  '';

  meta = with lib; {
    homepage = "https://github.com/wadahiro/keycloak-discord";
    description = "Keycloak Social Login extension for Discord";
    license = licenses.asl20;
    maintainers = with maintainers; [ mkg20001 ];
  };
}
