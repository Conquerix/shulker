# Expose independently enabled monitoring agents and the central hub.
{ ... }:
{
  imports = [
    ./agent.nix
    ./hub.nix
  ];
}
