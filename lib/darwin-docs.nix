{
  config,
  hostName,
  lib,
  pkgs,
  revision ? null,
}:

let
  inherit (builtins)
    attrNames
    concatLists
    isAttrs
    isBool
    map
    toString
    ;
  inherit (lib)
    concatStringsSep
    filter
    hasPrefix
    mapAttrsToList
    optionals
    ;

  escapeCell = value: lib.replaceStrings [ "|" "\n" ] [ "\\|" "<br>" ] (toString value);
  code = value: "`${escapeCell value}`";
  yesNo = value: if value then "yes" else "no";
  orNone = values: if values == [ ] then "_None._" else concatStringsSep ", " values;
  codeList = values: orNone (map code values);
  markdownTable =
    headers: rows:
    let
      renderRow = row: "| ${concatStringsSep " | " (map escapeCell row)} |\n";
    in
    renderRow headers + renderRow (map (_: "---") headers) + concatStringsSep "" (map renderRow rows);

  collectEnabled =
    path: value:
    if isAttrs value && value ? enable && isBool value.enable then
      optionals value.enable [ (concatStringsSep "." path) ]
    else if isAttrs value then
      concatLists (mapAttrsToList (name: child: collectEnabled (path ++ [ name ]) child) value)
    else
      [ ];

  enabledProfiles = collectEnabled [ ] (config.shulker.system.profiles or { });
  enabledModules = collectEnabled [ ] (config.shulker.system.modules or { });
  enabledUsers = collectEnabled [ ] (config.shulker.users or { });
  homeManagerUsers = attrNames (config.home-manager.users or { });
  systemUsers = filter (name: !(hasPrefix "_nixbld" name)) (attrNames (config.users.users or { }));
  systemPackages = map lib.getName (config.environment.systemPackages or [ ]);
  fontPackages = map lib.getName (config.fonts.packages or [ ]);
  launchDaemons = attrNames (config.launchd.daemons or { });
  launchAgents = attrNames (config.launchd.user.agents or { });
  homebrewBrews = config.homebrew.brews or [ ];
  homebrewCasks = config.homebrew.casks or [ ];
  homebrewMasApps = attrNames (config.homebrew.masApps or { });

  revisionLine = if revision == null then "" else "\nFlake revision: `${revision}`.\n";

  markdown = ''
    # ${hostName}

    This file is generated from the evaluated nix-darwin configuration. Change
    the host, profile, module, or Home Manager source rather than editing the
    generated report.
    ${revisionLine}
    ## System

    ${markdownTable
      [ "Setting" "Value" ]
      [
        [
          "Hostname"
          hostName
        ]
        [
          "Platform"
          config.nixpkgs.hostPlatform.system
        ]
        [
          "nix-darwin state version"
          (toString config.system.stateVersion)
        ]
        [
          "Primary user"
          (if config.system.primaryUser or null == null then "_None._" else code config.system.primaryUser)
        ]
        [
          "Enabled profiles"
          (codeList enabledProfiles)
        ]
        [
          "Enabled modules"
          (codeList enabledModules)
        ]
        [
          "Enabled Shulker users"
          (codeList enabledUsers)
        ]
        [
          "System users"
          (codeList systemUsers)
        ]
        [
          "Home Manager users"
          (codeList homeManagerUsers)
        ]
      ]
    }

    ## Security and Nix

    ${markdownTable
      [ "Setting" "Value" ]
      [
        [
          "Touch ID for sudo"
          (yesNo (config.security.pam.services.sudo_local.touchIdAuth or false))
        ]
        [
          "Nix enabled"
          (yesNo (config.nix.enable or true))
        ]
        [
          "Experimental features"
          (codeList (config.nix.settings.experimental-features or [ ]))
        ]
        [
          "Automatic garbage collection"
          (yesNo (config.nix.gc.automatic or false))
        ]
        [
          "Automatic store optimisation"
          (yesNo (config.nix.optimise.automatic or false))
        ]
      ]
    }

    ## Managed software

    ### System packages

    ${codeList systemPackages}

    ### Fonts

    ${codeList fontPackages}

    ### Homebrew

    ${markdownTable
      [ "Setting" "Value" ]
      [
        [
          "Enabled"
          (yesNo (config.homebrew.enable or false))
        ]
        [
          "Brews"
          (codeList homebrewBrews)
        ]
        [
          "Casks"
          (codeList homebrewCasks)
        ]
        [
          "Mac App Store apps"
          (codeList homebrewMasApps)
        ]
      ]
    }

    ## Launchd

    ${markdownTable
      [ "Scope" "Managed jobs" ]
      [
        [
          "System daemons"
          (codeList launchDaemons)
        ]
        [
          "User agents"
          (codeList launchAgents)
        ]
      ]
    }

    ## Operations

    Validate and apply this host:

    ```sh
    nix flake check --no-build --all-systems
    nix build .#darwinConfigurations.${hostName}.system
    darwin-rebuild check --flake .#${hostName}
    darwin-rebuild switch --flake .#${hostName}
    ```

    Inspect the current generation and managed jobs:

    ```sh
    darwin-rebuild --list-generations
    launchctl list
    nix store verify --all
    ```
  '';
in
pkgs.writeTextDir "${hostName}.md" markdown
