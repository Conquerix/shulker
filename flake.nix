{
  description = "Conquerix's Nix-Config";
  inputs = {
    #
    # ========= Official NixOS, Darwin, and HM Package Sources =========
    #
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    hardware.url = "github:nixos/nixos-hardware";
    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    #
    # ========= Utilities =========
    #
    impermanence.url = "github:nix-community/impermanence";

    # Declarative partitioning and formatting
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
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
    # Theming
    stylix.url = "github:danth/stylix/master";
    rose-pine-hyprcursor.url = "github:ndom91/rose-pine-hyprcursor";

    # Flake for the Eden emulator
    eden = {
      url = "github:conquerix/eden-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Flake for minecraft pelican panel
    pelican-panel = {
      url = "github:conquerix/nix-pelican-panel";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs =
    { self, nixpkgs, ... }@inputs:
    let
      inherit (self) outputs;

      #
      # ========= Architectures =========
      #
      forAllSystems = nixpkgs.lib.genAttrs [ "x86_64-linux" ];

      # ========== Extend lib with lib.custom ==========
      # NOTE: This approach allows lib.custom to propagate into hm
      # see: https://github.com/nix-community/home-manager/pull/3454
      lib = nixpkgs.lib.extend (
        self: super: { custom = import ./lib { inherit (nixpkgs) inputs lib; }; }
      );

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
      # Building configurations is available through `just rebuild` or `nixos-rebuild --flake .#hostname`
      nixosConfigurations = builtins.listToAttrs (
        map (host: {
          name = host;
          value = nixpkgs.lib.nixosSystem {
            specialArgs = { inherit inputs outputs lib; };
            modules = [
              inputs.home-manager.nixosModules.home-manager
              inputs.impermanence.nixosModule
              inputs.opnix.nixosModules.default
              inputs.eden.nixosModules.default
              inputs.pelican-panel.nixosModules.pelican-panel
              inputs.pelican-panel.nixosModules.wings
              (
                { inputs, ... }:
                {
                  networking.hostName = host;

                  # For compatibility with nix-shell, nix-build, etc.
                  environment.etc.nixpkgs.source = inputs.nixpkgs;

                  # Don't rely on the configuration to enable a flake-compatible version of Nix.
                  nix = {
                    extraOptions = "experimental-features = nix-command flakes";
                    nixPath = [ "nixpkgs=/etc/nixpkgs" ];
                    registry = {
                      self.flake = inputs.self;
                      nixpkgs = {
                        from = {
                          id = "nixpkgs";
                          type = "indirect";
                        };
                        flake = inputs.nixpkgs;
                      };
                    };
                  };

                  home-manager = {
                    useGlobalPkgs = true;
                    extraSpecialArgs = { inherit inputs; };
                    sharedModules = [ (import ./home) ];
                  };
                }
              )
              (import ./system/core)
              (import ./system/modules)
              (import ./system/profiles)
              (import ./system/users)
              (import ./system/hosts/${host})
            ];
          };
        }) (builtins.attrNames (builtins.readDir ./system/hosts))
      );

      #
      # ========= Packages =========
      #
      # Expose custom packages

      /*
        NOTE: This is only for exposing packages exterally; ie, `nix build .#packages.x86_64-linux.cd-gitroot`
        For internal use, these packages are added through the default overlay in `overlays/default.nix`
      */

      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ self.overlays.default ];
          };
        in
        nixpkgs.lib.packagesFromDirectoryRecursive {
          callPackage = nixpkgs.lib.callPackageWith pkgs;
          directory = ./pkgs;
        }
      );

      #
      # ========= Formatting =========
      #
      # Nix formatter available through 'nix fmt' https://github.com/NixOS/nixfmt
      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-rfc-style);
      # Pre-commit checks
      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        import ./checks.nix { inherit inputs system pkgs; }
      );
      #
      # ========= DevShell =========
      #
      # Custom shell for bootstrapping on new hosts, modifying nix-config, and secrets management
      devShells = forAllSystems (
        system:
        import ./shell.nix {
          pkgs = nixpkgs.legacyPackages.${system};
          checks = self.checks.${system};
        }
      );
    };
}
