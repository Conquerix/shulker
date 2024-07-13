{
  description = ''
    Shulker is my personal configuration. This repository contains configurations for all my systems.
  '';

  inputs = {
  
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    impermanence.url = "github:nix-community/impermanence";


    getchoo = {
      url = "github:getchoo/nix-exprs";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    opsm-nix.url = "github:conquerix/opsm-nix";

    # mail-server.url = "gitlab:simple-nixos-mailserver/nixos-mailserver";

    # agenix.url = "github:ryantm/agenix";
  };

  outputs = { self, ... }@inputs:
    with self.lib;
    let
      systems = [ "x86_64-linux" "x86_64-darwin" ];
      foreachSystem = genAttrs systems;
      pkgsBySystem = foreachSystem (
        system:
        import inputs.nixpkgs {
          inherit system;
          config = import ./nix/config.nix;
          overlays = self.overlays."${system}";
        }
      );
    in
    rec {
      lib = import ./lib { inherit inputs; } // inputs.nixpkgs.lib;

      devShells."x86_64-linux"= foreachSystem (system: import ./shell.nix { pkgs = pkgsBySystem."${system}"; });

      legacyPackages = pkgsBySystem;
      packages = foreachSystem (system: import ./nix/pkgs self system);
      overlay = foreachSystem (system: _final: _prev: self.packages."${system}");
      overlays = foreachSystem (
        system: with inputs; let
          ovs = attrValues (import ./nix/overlays self);
        in
        [
          (self.overlay."${system}")
        ] ++ ovs
      );

      homeManagerConfigurations = mapAttrs' mkHome {
        conquerix = { };
      };

      nixosConfigurations = mapAttrs' mkSystem {
        shulker    = { };
        phantom    = { };
        warden     = { };
        guardian   = { };
        vindicator = { };
        wither     = { };
        enderdragon= { };
        endermite  = { };
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
