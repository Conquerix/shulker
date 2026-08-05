{
  description = "Conquerix's Nix-Config";
  inputs = {
    #
    # ========= Official NixOS, Darwin, and HM Package Sources =========
    #
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    #
    # ========= Utilities =========
    #
    impermanence = {
      url = "github:nix-community/impermanence";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    # Pre-commit
    pre-commit-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Secrets management
    opnix = {
      url = "github:conquerix/opnix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Flake for the Eden emulator
    eden = {
      url = "github:conquerix/eden-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # SteamOS-like "Steam Machine" experience (gamescope gaming mode)
    jovian = {
      url = "github:Jovian-Experiments/Jovian-NixOS";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Flake for minecraft pelican panel
    pelican-panel = {
      url = "github:conquerix/nix-pelican-panel";
      inputs.nixpkgs.follows = "nixpkgs";
    };

  };
  outputs =
    {
      self,
      nixpkgs,
      nix-darwin,
      ...
    }@inputs:
    let
      inherit (self) outputs;

      #
      # ========= Architectures =========
      #
      forAllSystems = nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-darwin"
      ];

      nixosHostNames = builtins.attrNames (
        nixpkgs.lib.filterAttrs (_: type: type == "directory") (builtins.readDir ./system/hosts/nixos)
      );
      darwinHostNames = builtins.attrNames (
        nixpkgs.lib.filterAttrs (_: type: type == "directory") (builtins.readDir ./system/hosts/darwin)
      );

      # ========== Extend lib with lib.custom ==========
      # NOTE: This approach allows lib.custom to propagate into hm
      # see: https://github.com/nix-community/home-manager/pull/3454
      lib = nixpkgs.lib.extend (self: super: { custom = import ./lib { inherit (nixpkgs) lib; }; });

    in
    {
      #
      # ========= Overlays =========
      #
      # Custom modifications/overrides to upstream packages
      overlays = import ./overlays { inherit inputs; };

      #
      # ========= Host Configurations =========
      #
      # Rebuild a host with `nixos-rebuild switch --flake .#hostname`.
      nixosConfigurations = builtins.listToAttrs (
        map (host: {
          name = host;
          value = nixpkgs.lib.nixosSystem {
            specialArgs = {
              inherit
                inputs
                outputs
                lib
                ;
            };
            modules = [
              ({ networking.hostName = host; })
              ({ nixpkgs.overlays = [ outputs.overlays.default ]; })
              inputs.home-manager.nixosModules.home-manager
              inputs.impermanence.nixosModule
              inputs.opnix.nixosModules.default
              inputs.eden.nixosModules.default
              inputs.jovian.nixosModules.default
              inputs.pelican-panel.nixosModules.wings
              (import ./system/modules/common)
              (import ./system/modules/nixos)
              (import ./system/profiles/nixos)
              (import ./system/users)
              (import ./system/hosts/nixos/${host})
            ];
          };
        }) nixosHostNames
      );

      darwinConfigurations = builtins.listToAttrs (
        map (host: {
          name = host;
          value = nix-darwin.lib.darwinSystem {
            specialArgs = { inherit inputs outputs lib; };
            modules = [
              ({ networking.hostName = host; })
              ({ nixpkgs.overlays = [ outputs.overlays.default ]; })
              inputs.home-manager.darwinModules.home-manager
              (import ./system/modules/common)
              (import ./system/modules/darwin)
              (import ./system/profiles/darwin)
              (import ./system/users)
              (import ./system/hosts/darwin/${host})
            ];
          };
        }) darwinHostNames
      );

      # Host documentation is evaluated from the same merged configuration used
      # to build each host. Server-profile targets remain as compatibility
      # aliases for the corresponding NixOS host reports.
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          serverHostNames = builtins.filter (
            host: self.nixosConfigurations.${host}.config.shulker.system.profiles.server.enable
          ) nixosHostNames;
          nixosDocs = builtins.listToAttrs (
            map (host: {
              name = "host-docs-${host}";
              value = import ./lib/server-docs.nix {
                inherit lib pkgs;
                hostName = host;
                config = self.nixosConfigurations.${host}.config;
                revision = self.rev or self.dirtyRev or null;
              };
            }) nixosHostNames
          );
          darwinDocs = builtins.listToAttrs (
            map (host: {
              name = "host-docs-${host}";
              value = import ./lib/darwin-docs.nix {
                inherit lib pkgs;
                hostName = host;
                config = self.darwinConfigurations.${host}.config;
                revision = self.rev or self.dirtyRev or null;
              };
            }) darwinHostNames
          );
          hostDocs = nixosDocs // darwinDocs;
          serverDocs = builtins.listToAttrs (
            map (host: {
              name = "server-docs-${host}";
              value = nixosDocs."host-docs-${host}";
            }) serverHostNames
          );
          infrastructureData = import ./lib/infrastructure-data.nix {
            inherit darwinHostNames;
            darwinConfigurations = self.darwinConfigurations;
            external = builtins.fromJSON (builtins.readFile ./topology/public.json);
            hostNames = nixosHostNames;
            inherit lib;
            nixosConfigurations = self.nixosConfigurations;
            revision = self.rev or self.dirtyRev or null;
          };
          infrastructureDiagram = import ./lib/infrastructure-diagram.nix {
            data = infrastructureData;
            inherit lib pkgs;
          };
          checkedRebuild = import ./nix/checked-rebuild.nix {
            inherit pkgs;
            opnix = inputs.opnix.packages.${system}.default;
          };
        in
        serverDocs
        // hostDocs
        // {
          host-docs = pkgs.symlinkJoin {
            name = "host-docs";
            paths = builtins.attrValues hostDocs;
          };
          server-docs = pkgs.symlinkJoin {
            name = "server-docs";
            paths = builtins.attrValues serverDocs;
          };
          infrastructure-data = pkgs.writeTextDir "infrastructure.json" (
            builtins.toJSON infrastructureData + "\n"
          );
          infrastructure-diagram = infrastructureDiagram;
          wiki-docs = import ./lib/wiki-docs.nix {
            data = infrastructureData;
            inherit infrastructureDiagram;
            inherit lib pkgs;
          };
        }
        // lib.optionalAttrs pkgs.stdenv.isLinux {
          checked-rebuild = checkedRebuild;
        }
      );

      #
      # ========= Formatting =========
      #
      # Nix formatter available through 'nix fmt' https://github.com/NixOS/nixfmt
      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt);
      # Pre-commit checks
      checks = forAllSystems (system: import ./checks.nix { inherit inputs system; });
      #
      # ========= DevShell =========
      #
      # Development shell for maintaining and validating this configuration.
      devShells = forAllSystems (
        system:
        import ./shell.nix {
          pkgs = nixpkgs.legacyPackages.${system};
          checks = self.checks.${system};
        }
      );
    };
}
