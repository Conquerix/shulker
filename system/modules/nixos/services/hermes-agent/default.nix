# Named agents share one implementation; capabilities are opt-in per instance.
{ ... }:
{
  imports = [
    ./options.nix
    ./instances.nix
    ./host-administration.nix
  ];
}
