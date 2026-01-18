{
  lib,
  ...
}:
with lib;
{
  config = {
    networking = {
      knownNetworkServices = [
        "Wi-Fi"
        "Thunderbolt Bridge"
      ];
      dns = [
        "9.9.9.9"
        "149.112.112.112"
      ];
    };
  };
}
