{
  description = ''
    Shulker is my personal configuration. This repository contains configurations for all my systems.
  '';

  inputs = {
  
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    impermanence.url = "github:nix-community/impermanence";

    mail-server.url = "gitlab:simple-nixos-mailserver/nixos-mailserver";

    agenix.url = "github:ryantm/agenix";
  };

  outputs = { self, ... }@inputs:
    with self.lib;
    let
      systems = [ "x86_64-linux" ];
      foreachSystem = genAttrs systems;
      pkgsBySystem = foreachSystem (
        system:
        import inputs.nixpkgs {
          inherit system;
          config = import ./nix/config.nix;
        }
      );
    in
    rec {
      inherit pkgsBySystem;
      lib = import ./lib { inherit inputs; } // inputs.nixpkgs.lib;

      devShells."x86_64-linux"= foreachSystem (system: import ./shell.nix { pkgs = pkgsBySystem."${system}"; });

      packages = foreachSystem (system: import ./nix/pkgs self system);

      homeManagerConfigurations = mapAttrs' mkHome {
        conquerix = { };
      };

      nixosConfigurations = mapAttrs' mkSystem {
        shulker    = { };
        phantom    = { };
        warden     = { };
        guardian   = { };
        vindicator = { };
      };

      # Convenience output that aggregates the output configurations.
     top =
       let
       nixtop = genAttrs
         (builtins.attrNames inputs.self.nixosConfigurations)
         (attr: inputs.self.nixosConfigurations.${attr}.config.system.build.toplevel);
       hometop = genAttrs
         (builtins.attrNames inputs.self.homeManagerConfigurations)
         (attr: inputs.self.homeManagerConfigurations.${attr}.activationPackage);
       in
       nixtop // hometop;
    };
}
