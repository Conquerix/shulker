# Assemble fleet configurations, validation checks, and generated operator documentation.
{
  description = "Conquerix's Nix-Config";
  inputs = {
    # Follow one nixpkgs input so system modules and user packages share the same revision.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # External modules provide persistence, secrets, checks, and application integrations.
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

      # Build tools and reports for Linux and Apple Silicon development hosts.
      forAllSystems = nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-darwin"
      ];

      # Each direct host directory becomes a flake configuration with the same name.
      nixosHostNames = builtins.attrNames (
        nixpkgs.lib.filterAttrs (_: type: type == "directory") (builtins.readDir ./system/hosts/nixos)
      );
      darwinHostNames = builtins.attrNames (
        nixpkgs.lib.filterAttrs (_: type: type == "directory") (builtins.readDir ./system/hosts/darwin)
      );

      # Extend lib so the same custom helpers also reach Home Manager modules.
      # https://github.com/nix-community/home-manager/pull/3454
      lib = nixpkgs.lib.extend (self: super: { custom = import ./lib { inherit (nixpkgs) lib; }; });

    in
    {
      # Apply local package fixes to every host.
      overlays = import ./overlays { inherit inputs; };

      # Common module availability; each host selects its profiles and enabled services.
      # Rebuild a host with `sudo shulker-rebuild switch --flake .#hostname`.
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

      # macOS shares common modules and users, with its own platform modules and profiles.
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
          # Never feed private or live API data directly into published documentation.
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
            serviceSourceDir = ./system/modules/nixos/services;
            wikiSourceDir = ./docs/wiki;
          };
        }
        # The deployment wrapper depends on nixos-rebuild and is Linux-only.
        // lib.optionalAttrs pkgs.stdenv.isLinux {
          checked-rebuild = checkedRebuild;
        }
      );

      # Keep local formatting aligned with the validation hooks.
      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt);
      # Export the same contracts used by local validation and CI.
      checks = forAllSystems (
        system:
        import ./checks.nix {
          inherit inputs self system;
        }
      );
      # Development tools inherit their hooks and packages from these checks.
      devShells = forAllSystems (
        system:
        import ./shell.nix {
          pkgs = nixpkgs.legacyPackages.${system};
          checks = self.checks.${system};
        }
      );
    };
}
