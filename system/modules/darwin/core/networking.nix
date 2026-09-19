{ ... }:
{
  # Apply deterministic DNS to the macOS network services managed by nix-darwin.
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
