{ stdenv, lib, fetchFromGitHub, buildGoModule }:

buildGoModule rec {
  pname = "mc-monitor";
  version = "0.12.7";

  src = fetchFromGitHub {
    owner = "itzg";
    repo = "mc-monitor";
    rev = version;
    sha256 = "gdPB1tOGVgD+KUjGNg9QqEu3NGJdde1rUC5Rwe2PxrM=";
  };

  vendorHash = "sha256-WQIamsAg2ARmGN2FNoNtvcywZ9haI2Xcmfh0dGy3npk=";

  meta = with lib; {
    description = "Monitor the status of Minecraft servers and provides Prometheus exporter and Influx line protocol output ";
    homepage = "https://github.com/itzg/mc-monitor";
    license = licenses.mit;
    maintainers = with maintainers; [ conquerix ];
  };
}
