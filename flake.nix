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
    impermanence.url = "github:nix-community/impermanence";

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
      # Building configurations is available through `just rebuild` or `nixos-rebuild --flake .#hostname`
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
              inputs.pelican-panel.nixosModules.pelican-panel
              inputs.pelican-panel.nixosModules.wings
              (import ./system/modules/common)
              (import ./system/modules/nixos)
              (import ./system/profiles/nixos)
              (import ./system/users)
              (import ./system/hosts/nixos/${host})
            ];
          };
        }) (builtins.attrNames (builtins.readDir ./system/hosts/nixos))
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
        }) (builtins.attrNames (builtins.readDir ./system/hosts/darwin))
      );

      #
      # ========= Formatting =========
      #
      # Nix formatter available through 'nix fmt' https://github.com/NixOS/nixfmt
      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-rfc-style);
      # Pre-commit checks
      checks = forAllSystems (system: import ./checks.nix { inherit inputs system; });
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
