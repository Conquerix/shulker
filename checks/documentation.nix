# Validate service discovery, public documentation, and safe Wiki publication.
{
  self,
  system,
  pkgs,
  ...
}:

let
  witherHostDocs = self.packages.${system}."host-docs-wither";
  infrastructureData = self.packages.${system}.infrastructure-data;
  wikiDocs = self.packages.${system}.wiki-docs;
  # Store-backed fixtures exercise report names, link chains, and escaping targets.
  wikiSyncWardenReport = pkgs.writeTextDir "warden.md" "# Warden\n";
  wikiSyncDecoyReport = pkgs.writeTextDir "shulker.md" "# Shulker\n";
  wikiSyncWardenReportName = builtins.baseNameOf (toString wikiSyncWardenReport);
  wikiSyncWrongOutputName = pkgs.runCommand "not-host-docs" { } ''
    mkdir "$out"
    ln -s ${wikiSyncWardenReport}/warden.md "$out/warden.md"
  '';
  wikiSyncMismatchedReport = pkgs.runCommand "host-docs" { } ''
    mkdir "$out"
    ln -s ${wikiSyncDecoyReport}/shulker.md "$out/warden.md"
  '';
  wikiSyncNoncanonicalReport = pkgs.runCommand "host-docs" { } ''
    mkdir "$out"
    ln -s ${wikiSyncWardenReport}/../${wikiSyncWardenReportName}/warden.md "$out/warden.md"
  '';
  wikiSyncIntermediateWardenReport = pkgs.runCommand "warden.md" { } ''
    mkdir "$out"
    ln -s ${wikiSyncWardenReport}/warden.md "$out/warden.md"
  '';
  wikiSyncChainedReport = pkgs.runCommand "host-docs" { } ''
    mkdir "$out"
    ln -s ${wikiSyncIntermediateWardenReport}/warden.md "$out/warden.md"
  '';
  wikiSyncEscapingReport = pkgs.runCommand "host-docs" { } ''
    mkdir "$out"
    ln -s /etc/passwd "$out/warden.md"
  '';
  wikiSyncRelativeReport = pkgs.runCommand "host-docs" { } ''
    mkdir "$out"
    ln -s ../${wikiSyncWardenReportName}/warden.md "$out/warden.md"
  '';
  wikiSyncLineBreakReport = pkgs.runCommand "host-docs" { } ''
    mkdir "$out"
    report_target=${wikiSyncWardenReport}/warden.md
    ln -s "$report_target"$'\r\n' "$out/warden.md"
  '';
  # The explicit inventory catches accidental service moves or discovery expansion.
  retainedServices = [
    "backup"
    "beszel"
    "forgejo"
    "git-pages"
    "hermes-agent"
    "home-assistant"
    "immich"
    "newt"
    "nextcloud"
    "ollama"
    "pangolin"
    "paperless"
    "pelican"
    "plex"
    "pocket-id"
    "seafile"
    "sunshine"
    "taskview"
    "torrent"
    "webdav"
  ];
  excludedCapabilities = [
    {
      path = "core";
      type = "directory";
    }
    {
      path = "containers.nix";
      type = "regular";
    }
    {
      path = "impermanence.nix";
      type = "regular";
    }
    {
      path = "nvidia.nix";
      type = "regular";
    }
    {
      path = "steam.nix";
      type = "regular";
    }
    {
      path = "yubikey.nix";
      type = "regular";
    }
  ];
  nixosModuleRoot = ../. + "/system/modules/nixos";
  serviceModuleRoot = nixosModuleRoot + "/services";
  nixosModuleEntries = builtins.readDir nixosModuleRoot;
  serviceModuleEntries = builtins.readDir serviceModuleRoot;
  directServiceDirectories = pkgs.lib.sort builtins.lessThan (
    builtins.attrNames (
      pkgs.lib.filterAttrs (_: entryType: entryType == "directory") serviceModuleEntries
    )
  );
  nixosModuleLib = pkgs.lib // {
    custom = import ../lib { lib = pkgs.lib; };
  };
  nixosModuleManifest = import (nixosModuleRoot + "/default.nix") { lib = nixosModuleLib; };
  serviceModuleManifest = import (serviceModuleRoot + "/default.nix") { lib = nixosModuleLib; };
  serviceLayoutContract =
    let
      serviceFilesAreCanonical =
        service:
        let
          entries = builtins.readDir (serviceModuleRoot + "/${service}");
        in
        (entries."default.nix" or null) == "regular"
        && (entries."README.md" or null) == "regular"
        && builtins.readFile (serviceModuleRoot + "/${service}/README.md") != "";
      expectedRootEntries = pkgs.lib.sort builtins.lessThan (
        [
          "default.nix"
          "services"
        ]
        ++ map (capability: capability.path) excludedCapabilities
      );
      expectedServiceRootEntries = pkgs.lib.sort builtins.lessThan (
        [
          "README.md"
          "default.nix"
        ]
        ++ retainedServices
      );
      importedServicePaths = map toString (serviceModuleManifest.imports or [ ]);
      directServicePaths = pkgs.lib.sort builtins.lessThan (
        map (name: toString (serviceModuleRoot + "/${name}")) directServiceDirectories
      );
      rootImportNames = map (
        path: pkgs.lib.removeSuffix ".nix" (builtins.baseNameOf path)
      ) nixosModuleManifest.imports;
      expectedRootImportNames = [
        "backup"
        "beszel"
        "containers"
        "core"
        "forgejo"
        "git-pages"
        "hermes-agent"
        "home-assistant"
        "immich"
        "impermanence"
        "newt"
        "nextcloud"
        "nvidia"
        "ollama"
        "pangolin"
        "paperless"
        "pelican"
        "plex"
        "pocket-id"
        "seafile"
        "steam"
        "sunshine"
        "taskview"
        "torrent"
        "webdav"
        "yubikey"
      ];
    in
    assert builtins.length retainedServices == 20;
    assert builtins.length excludedCapabilities == 6;
    assert directServiceDirectories == retainedServices;
    assert builtins.all serviceFilesAreCanonical retainedServices;
    assert builtins.all (
      capability: nixosModuleEntries.${capability.path} or null == capability.type
    ) excludedCapabilities;
    assert builtins.all (
      capability: serviceModuleEntries.${builtins.baseNameOf capability.path} or null == null
    ) excludedCapabilities;
    assert nixosModuleEntries."default.nix" == "regular";
    assert nixosModuleEntries.services == "directory";
    assert builtins.attrNames nixosModuleEntries == expectedRootEntries;
    assert builtins.attrNames serviceModuleEntries == expectedServiceRootEntries;
    assert importedServicePaths == directServicePaths;
    assert rootImportNames == expectedRootImportNames;
    true;
  serviceRunbooks = import ../lib/service-runbooks.nix { lib = pkgs.lib; };
  # Force lazy discovery results so malformed names and collisions fail evaluation.
  serviceRunbookContract =
    let
      evaluate = arguments: builtins.tryEval (builtins.deepSeq (serviceRunbooks arguments) true);
      valid = {
        discovered = [
          {
            folder = "webdav";
            readmeType = "regular";
            content = "# WebDAV\n";
            source = "fixture/webdav/README.md";
          }
        ];
        reservedPageNames = [ "Home.md" ];
      };
      invalid = overrides: valid // overrides;
      record = builtins.head valid.discovered;
      invalidRecord = updates: invalid { discovered = [ (record // updates) ]; };
      duplicateDiscovered = invalid {
        discovered = [
          record
          (record // { source = "fixture/duplicate/README.md"; })
        ];
      };
      caseFoldedDiscovered = invalid {
        discovered = [
          record
          (
            record
            // {
              content = "# Webdav\n";
              source = "fixture/case-folded/README.md";
            }
          )
        ];
      };
      hostReservedDiscovered = invalid {
        discovered = [
          {
            folder = "host-webdav";
            readmeType = "regular";
            content = "# Host WebDAV\n";
            source = "fixture/host-webdav/README.md";
          }
        ];
        reservedPageNames = [ "Service-Host-WebDAV.md" ];
      };
    in
    assert (evaluate valid).success;
    assert
      !(evaluate (invalidRecord {
        readmeType = null;
      })).success;
    assert
      !(evaluate (invalidRecord {
        readmeType = "symlink";
      })).success;
    assert
      !(evaluate (invalidRecord {
        content = "";
      })).success;
    assert
      !(evaluate (invalidRecord {
        content = "# WebDAV!\n";
      })).success;
    assert
      !(evaluate (invalidRecord {
        content = "# Web  DAV\n";
      })).success;
    assert
      !(evaluate (invalidRecord {
        folder = "web--dav";
      })).success;
    assert
      !(evaluate (invalidRecord {
        folder = "other";
      })).success;
    assert !(evaluate duplicateDiscovered).success;
    assert !(evaluate caseFoldedDiscovered).success;
    assert !(evaluate hostReservedDiscovered).success;
    assert
      !(evaluate (invalid {
        reservedPageNames = [ "Service-WebDAV.md" ];
      })).success;
    assert
      !(evaluate (invalid {
        reservedPageNames = [ "service-webdav.md" ];
      })).success;
    assert
      !(evaluate (invalid {
        reservedPageNames = [
          "Home.md"
          "Home.md"
        ];
      })).success;
    assert
      !(evaluate (invalid {
        reservedPageNames = [
          "Home.md"
          "home.md"
        ];
      })).success;
    true;
in
{
  validation = serviceLayoutContract && serviceRunbookContract;
  checks = {
    service-module-layout-contract = pkgs.runCommand "service-module-layout-contract" { } ''
      test -f ${serviceModuleRoot}/default.nix
      test -f ${serviceModuleRoot}/README.md
      test ! -L ${serviceModuleRoot}/default.nix
      test ! -L ${serviceModuleRoot}/README.md
      touch "$out"
    '';

    # Build checks cover rendered content and publication wiring beyond Nix assertions.
    wiki-docs-contract =
      pkgs.runCommand "wiki-docs-contract"
        {
          nativeBuildInputs = [
            pkgs.bash
            pkgs.coreutils
            pkgs.findutils
            pkgs.gawk
            pkgs.gnugrep
            pkgs.python3
          ];
        }
        ''
          source_root=${../.}/docs/wiki
          service_source_root=${../.}/system/modules/nixos/services
          root_readme=${../README.md}
          agents=${../AGENTS.md}
          server_docs_source=${../lib/server-docs.nix}
          wiki_workflow=${../.github/workflows/wiki.yml}
          check_workflow=${../.github/workflows/check.yml}
          automation_guide=${../.github/AUTOMATION.md}
          development_guide=${../docs/wiki/project/development.md}
          host_docs_guide=${../system/hosts/nixos/README.md}
          wiki_generator_source=${../lib/wiki-docs.nix}
          source_validator=${../scripts/validate-wiki-source.py}
          host_docs=${self.packages.${system}.host-docs}
          wither_host_docs=${witherHostDocs}/wither.md
          infrastructure_json=${infrastructureData}/infrastructure.json

          readme_lines="$(wc -l < "$root_readme")"
          if [ "$readme_lines" -ge 200 ]; then
            echo "README must remain below 200 lines; found $readme_lines" >&2
            exit 1
          fi

          if [ -e "${../.}/.github/README.md" ]; then
            echo '.github/README.md shadows the project README on GitHub' >&2
            exit 1
          fi

          grep -F -- '](https://github.com/Conquerix/shulker/wiki)' "$root_readme" >/dev/null
          grep -F -- '](https://github.com/Conquerix/shulker/wiki/Automation)' "$root_readme" >/dev/null
          grep -F -- '[version-controlled sources](docs/wiki/)' "$root_readme" >/dev/null
          if grep -E -- '^- \[[^]]+\]\(docs/wiki/(services|operations|project)/' "$root_readme" >/dev/null; then
            echo 'README lists individual Wiki entries instead of routing through the Wiki table of contents' >&2
            exit 1
          fi

          grep -F -x -- '## Table of contents' "${wikiDocs}/Home.md" >/dev/null
          if grep -F -x -- '## Browse the documentation' "${wikiDocs}/Home.md" >/dev/null; then
            echo 'Wiki Home retains the former documentation table heading' >&2
            exit 1
          fi

          if ! grep -F -x -- 'name: Publish repository Wiki' "$wiki_workflow" >/dev/null; then
            echo 'Wiki workflow name is not Publish repository Wiki' >&2
            exit 1
          fi
          if ! grep -F -x -- '      - "docs/wiki/**"' "$wiki_workflow" >/dev/null; then
            echo 'Wiki workflow does not publish changes under docs/wiki/**' >&2
            exit 1
          fi
          if ! grep -F -x -- '          git -C wiki commit -m "docs: publish repository Wiki"' "$wiki_workflow" >/dev/null; then
            echo 'Wiki workflow uses the wrong publication commit subject' >&2
            exit 1
          fi
          if ! grep -F -x -- '          cp -L wiki-docs-result/wiki-pages.txt generated-wiki-docs/' "$check_workflow" >/dev/null; then
            echo 'Checks workflow omits wiki-pages.txt from the generated artifact' >&2
            exit 1
          fi
          if ! grep -F -x -- '    if: github.ref_name == github.event.repository.default_branch' "$wiki_workflow" >/dev/null; then
            echo 'Wiki publication is not restricted to the default branch for every event' >&2
            exit 1
          fi
          wiki_sync_run='        run: bash scripts/sync-server-wiki.sh "$GITHUB_WORKSPACE/host-docs-result" wiki wiki-docs-result'
          if [ "$(grep -F -x -c -- "$wiki_sync_run" "$wiki_workflow")" -ne 1 ]; then
            echo 'Wiki workflow does not pass the canonical absolute host-docs out-link to the synchronizer' >&2
            exit 1
          fi

          publication_suite_run='        run: nix build --no-link .#checks.x86_64-linux.wiki-publication-contract-suite'
          for workflow in "$wiki_workflow" "$check_workflow"; do
            if [ "$(grep -F -x -c -- "$publication_suite_run" "$workflow")" -ne 1 ]; then
              echo "Workflow does not build the exact Wiki publication contract suite: $workflow" >&2
              exit 1
            fi
          done

          for wiki_step in \
            'Refresh sanitized Pangolin topology' \
            'Validate Wiki publication contracts' \
            'Build Wiki documentation' \
            'Clone Wiki'
          do
            if [ "$(grep -F -x -c -- "      - name: $wiki_step" "$wiki_workflow")" -ne 1 ]; then
              echo "Wiki workflow does not contain exactly one '$wiki_step' step" >&2
              exit 1
            fi
          done

          wiki_refresh_line="$(grep -F -x -n -- '      - name: Refresh sanitized Pangolin topology' "$wiki_workflow" | cut -d: -f1)"
          wiki_validation_line="$(grep -F -x -n -- '      - name: Validate Wiki publication contracts' "$wiki_workflow" | cut -d: -f1)"
          wiki_build_line="$(grep -F -x -n -- '      - name: Build Wiki documentation' "$wiki_workflow" | cut -d: -f1)"
          wiki_suite_line="$(grep -F -x -n -- "$publication_suite_run" "$wiki_workflow" | cut -d: -f1)"
          wiki_clone_line="$(grep -F -x -n -- '      - name: Clone Wiki' "$wiki_workflow" | cut -d: -f1)"
          check_suite_line="$(grep -F -x -n -- "$publication_suite_run" "$check_workflow" | cut -d: -f1)"
          artifact_build_line="$(grep -F -x -n -- '      - name: Build generated Wiki documentation' "$check_workflow" | cut -d: -f1)"
          if ! test "$wiki_refresh_line" -lt "$wiki_validation_line" \
            || ! test "$wiki_validation_line" -lt "$wiki_build_line" \
            || ! test "$wiki_build_line" -lt "$wiki_clone_line"; then
            echo 'Wiki workflow must refresh topology, validate contracts, build documentation, then clone the Wiki' >&2
            exit 1
          fi
          test "$wiki_suite_line" -lt "$wiki_clone_line"
          test "$check_suite_line" -lt "$artifact_build_line"

          grep -F -- 'The repository Wiki is publication output, not an authoring surface.' "$automation_guide" >/dev/null
          grep -F -- 'Fleet and project runbooks come from `docs/wiki/`' "$automation_guide" >/dev/null
          grep -F -- 'Canonical service runbooks' "$automation_guide" >/dev/null
          grep -F -- 'Service pages originate only from' "$automation_guide" >/dev/null
          grep -F -- 'Evaluated pages are built from Nix configuration' "$automation_guide" >/dev/null
          grep -F -- 'Host pages come from evaluated host reports' "$automation_guide" >/dev/null
          grep -F -- '`wiki-pages.txt` is the non-host page inventory.' "$automation_guide" >/dev/null

          for authored_output in \
            Operations-Backup-and-Restore.md \
            Operations-Security-and-Recovery.md \
            Project-Development.md
          do
            grep -F -- "\`$authored_output\`" "$automation_guide" >/dev/null
          done

          grep -F -- '`GITHUB_TOKEN`' "$automation_guide" >/dev/null
          grep -F -- '`contents: write`' "$automation_guide" >/dev/null
          grep -F -- '`PANGOLIN_TOPOLOGY_API_KEY`' "$automation_guide" >/dev/null
          grep -F -- 'raw API responses in a private temporary directory' "$automation_guide" >/dev/null

          for expected in \
            '`topology/public.json` is the sanitized boundary' \
            '`topology/private*.json`' \
            'root-only, reversible bootstrap helper' \
            'rolls back if the Pangolin API does not become healthy' \
            'briefly restarts Pangolin and Traefik'
          do
            grep -F -- "$expected" "$automation_guide" >/dev/null
          done
          grep -F -x -- 'PANGOLIN_API_ENDPOINT=https://api.example.com \' "$automation_guide" >/dev/null
          grep -F -x -- 'PANGOLIN_ORG_ID=example \' "$automation_guide" >/dev/null
          grep -F -x -- 'PANGOLIN_API_KEY=... \' "$automation_guide" >/dev/null
          grep -F -x -- 'scripts/fetch-pangolin-topology.sh' "$automation_guide" >/dev/null
          grep -F -x -- 'sudo nix shell nixpkgs#yq-go --command \' "$automation_guide" >/dev/null
          grep -F -x -- '  scripts/configure-pangolin-integration-api.sh api.example.com' "$automation_guide" >/dev/null

          grep -F -- \
            '[Pangolin topology operations](https://github.com/Conquerix/shulker/blob/dev/.github/AUTOMATION.md#pangolin-topology-enrichment)' \
            "$development_guide" >/dev/null

          for expected in \
            'Newly discovered NixOS and nix-darwin hosts automatically receive a report and appear in the Wiki.' \
            '`server-docs` and `server-docs-<host>` remain compatibility aliases for server-profile hosts.'
          do
            grep -F -- "$expected" "$host_docs_guide" >/dev/null
          done

          for documentation in "$development_guide" "$wiki_generator_source" "${wikiDocs}/Automation.md"; do
            grep -F -- 'Publish repository Wiki' "$documentation" >/dev/null
            grep -F -- 'docs/wiki/' "$documentation" >/dev/null
            grep -F -- 'service READMEs' "$documentation" >/dev/null
            grep -F -- 'evaluated non-host pages from Nix' "$documentation" >/dev/null
            grep -F -- 'host pages from evaluated `host-docs` reports' "$documentation" >/dev/null
            if grep -F -- 'Publish infrastructure Wiki' "$documentation" >/dev/null; then
              echo "Documentation retains the stale Wiki workflow name: $documentation" >&2
              exit 1
            fi
          done
          grep -F -- 'serviceReadmes[Direct service READMEs]' "$wiki_generator_source" >/dev/null
          grep -F -- 'serviceReadmes[Direct service READMEs]' "${wikiDocs}/Automation.md" >/dev/null
          if grep -F -- 'synchronizes generated Wiki pages' "$wiki_generator_source" "${wikiDocs}/Automation.md" >/dev/null; then
            echo 'Automation retains the generated-only publication claim' >&2
            exit 1
          fi
          tr '\n' ' ' < "$development_guide" > "$TMPDIR/development-guide-single-line"
          if grep -F -- 'publish the host reports' "$TMPDIR/development-guide-single-line" >/dev/null; then
            echo 'Development guide retains the host-only publication claim' >&2
            exit 1
          fi

          for former_heading in \
            '## Hermes WebUI and native clients' \
            '## GrapheneOS WebDAV backups' \
            '## Seafile family files' \
            '## Immich family photos' \
            '## Paperless family documents'
          do
            if grep -F -x -- "$former_heading" "$root_readme" >/dev/null; then
              echo "README retains former service runbook heading: $former_heading" >&2
              exit 1
            fi
          done

          expected_agent_routes="$TMPDIR/expected-agent-routes.txt"
          printf '%s\n' \
            system/modules/nixos/services/ \
            docs/wiki/operations/security-and-recovery.md \
            docs/wiki/operations/backup-and-restore.md \
            docs/wiki/project/development.md \
            system/hosts/nixos/README.md \
            .github/AUTOMATION.md > "$expected_agent_routes"
          actual_agent_routes="$TMPDIR/actual-agent-routes.txt"
          awk '
            $0 == "## Documentation routing" { in_section = 1; next }
            in_section && /^## / { exit }
            in_section {
              remaining = $0
              while (match(remaining, /\]\([^)]*\)/)) {
                print substr(remaining, RSTART + 2, RLENGTH - 3)
                remaining = substr(remaining, RSTART + RLENGTH)
              }
            }
          ' "$agents" > "$actual_agent_routes"
          cmp "$expected_agent_routes" "$actual_agent_routes"

          if [ -e "$source_root/services" ]; then
            echo 'docs/wiki/services must be absent after service runbook migration' >&2
            exit 1
          fi
          if grep -F -- 'legacyServiceRunbooks' "$wiki_generator_source" >/dev/null; then
            echo 'Wiki generator retains the repository legacy-runbook binding' >&2
            exit 1
          fi

          private_ipv4_pattern='(^|[^0-9])(10(\.[0-9]{1,3}){3}|172\.(1[6-9]|2[0-9]|3[01])(\.[0-9]{1,3}){2}|192\.168(\.[0-9]{1,3}){2})([^0-9]|$)'
          for public_document in "$host_docs"/*.md "${wikiDocs}"/*.md; do
            if grep -Eq -- "$private_ipv4_pattern" "$public_document"; then
              echo "Public documentation contains a private IPv4 address: $(basename "$public_document")" >&2
              exit 1
            fi
          done

          if [ "$(grep -F -c -- '| Steam |' "$wither_host_docs")" -ne 1 ]; then
            echo 'Wither host documentation does not retain its evaluated Steam service row' >&2
            exit 1
          fi
          python3 - "$infrastructure_json" <<'PY'
          import json
          import sys

          with open(sys.argv[1], encoding="utf-8") as source:
              data = json.load(source)

          wither = next((host for host in data["hosts"] if host["name"] == "wither"), None)
          if wither is None:
              raise SystemExit("evaluated infrastructure data has no Wither host")

          steam = [service for service in wither["services"] if service["key"] == "steam"]
          expected = [{"category": "gaming", "endpoint": None, "key": "steam", "name": "Steam"}]
          if steam != expected:
              raise SystemExit(f"unexpected Wither Steam inventory: {steam!r}")
          PY

          for service_page in Service-Immich Service-Paperless Service-Seafile; do
            wiki_url="https://github.com/Conquerix/shulker/wiki/$service_page"
            test "$(grep -F -c -- "$wiki_url" "$server_docs_source")" -eq 1
          done
          if grep -F -- 'repository README' "$server_docs_source" >/dev/null; then
            echo "Generated server documentation routes operators to the repository README" >&2
            exit 1
          fi

          if [ ! -f "${wikiDocs}/wiki-pages.txt" ]; then
            echo "wiki-pages.txt is missing from wiki-docs" >&2
            exit 1
          fi

          generated_names='Automation.md Fleet.md Home.md Infrastructure.md Operations.md Public-Services.md Servers.md Services.md _Footer.md _Sidebar.md'
          authored_pairs="$TMPDIR/authored-service-and-static-pages.tsv"
          printf '%s\t%s\t%s\n' \
            static "$source_root/operations/backup-and-restore.md" Operations-Backup-and-Restore.md \
            static "$source_root/operations/security-and-recovery.md" Operations-Security-and-Recovery.md \
            static "$source_root/project/development.md" Project-Development.md > "$authored_pairs"

          while IFS= read -r -d "" directory; do
            folder="$(basename "$directory")"
            case "$folder" in
              *[!a-z0-9-]* | -* | *- | *--*)
                echo "$folder: invalid service folder" >&2
                exit 1
                ;;
            esac
            readme="$directory/README.md"
            if [ ! -f "$readme" ] || [ -L "$readme" ] || [ ! -s "$readme" ]; then
              echo "$folder: README.md must be a non-empty regular file" >&2
              exit 1
            fi
            first_line="$(head -n 1 "$readme")"
            title="''${first_line#\# }"
            if [ "$first_line" != "# $title" ] || ! printf '%s\n' "$title" | grep -Eq '^[A-Za-z0-9]+( [A-Za-z0-9]+)*$'; then
              echo "$folder: invalid README title" >&2
              exit 1
            fi
            normalized="$(printf '%s' "$title" | tr '[:upper:] ' '[:lower:]-')"
            if [ "$normalized" != "$folder" ]; then
              echo "$folder: title does not normalize to folder" >&2
              exit 1
            fi
            page_name="Service-$(printf '%s' "$title" | tr ' ' '-').md"
            printf '%s\t%s\t%s\n' discovered "$readme" "$page_name" >> "$authored_pairs"
          done < <(find "$service_source_root" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)

          if find "$service_source_root" -mindepth 1 -maxdepth 1 -type l -print -quit | grep -q .; then
            echo 'services root contains a symlink' >&2
            exit 1
          fi
          while IFS= read -r -d "" entry; do
            name="$(basename "$entry")"
            if [ "$name" != README.md ] && [ "$name" != default.nix ] && [ ! -d "$entry" ]; then
              echo "services root contains unsafe entry: $name" >&2
              exit 1
            fi
          done < <(find "$service_source_root" -mindepth 1 -maxdepth 1 -print0)

          cut -f3 "$authored_pairs" | sort > "$TMPDIR/authored-page-names.txt"
          if [ "$(sort -u "$TMPDIR/authored-page-names.txt" | wc -l)" -ne "$(wc -l < "$TMPDIR/authored-page-names.txt")" ]; then
            echo 'duplicate authored Wiki page name' >&2
            exit 1
          fi
          tr '[:upper:]' '[:lower:]' < "$TMPDIR/authored-page-names.txt" | sort -u > "$TMPDIR/casefolded-authored-page-names.txt"
          if [ "$(wc -l < "$TMPDIR/casefolded-authored-page-names.txt")" -ne "$(wc -l < "$TMPDIR/authored-page-names.txt")" ]; then
            echo 'case-folded authored Wiki page collision' >&2
            exit 1
          fi
          while IFS= read -r page_name; do
            case "$page_name" in
              Host-* | host-*)
                echo "$page_name: reserved host page name" >&2
                exit 1
                ;;
            esac
            if printf '%s\n' "$generated_names" | tr ' ' '\n' | grep -Fxiq -- "$page_name"; then
              echo "$page_name: generated page name collision" >&2
              exit 1
            fi
          done < "$TMPDIR/authored-page-names.txt"

          expected_manifest="$TMPDIR/expected-wiki-pages.txt"
          {
            printf '%s\n' $generated_names
            cat "$TMPDIR/authored-page-names.txt"
          } | sort -u > "$expected_manifest"
          cmp "$expected_manifest" "${wikiDocs}/wiki-pages.txt"
          find "${wikiDocs}" -maxdepth 1 -type f -name '*.md' ! -name 'Host-*' -printf '%f\n' \
            | sort -u > "$TMPDIR/wiki-page-basenames.txt"
          cmp "$expected_manifest" "$TMPDIR/wiki-page-basenames.txt"

          bash ${../tests/wiki-source-validator.sh} "$source_validator"

          while IFS=$'\t' read -r origin source page_name; do
            test -f "$source"
            test ! -L "$source"
            test -s "$source"
            python3 "$source_validator" "$source"
            cmp "$source" "${wikiDocs}/$page_name"
            page_slug="''${page_name%.md}"
            grep -F -- "($page_slug)" "${wikiDocs}/Home.md" >/dev/null
            grep -F -- "($page_slug)" "${wikiDocs}/_Sidebar.md" >/dev/null
            if [ "$origin" != static ]; then
              service_title="$(printf '%s' "''${page_slug#Service-}" | tr '-' ' ')"
              grep -Fx -- "  - [$service_title]($page_slug)" "${wikiDocs}/_Sidebar.md" >/dev/null
              grep -F -- "($page_slug)" "${wikiDocs}/Services.md" >/dev/null
            fi
          done < "$authored_pairs"

          touch "$out"
        '';

    # Use real store outputs with the isolated synchronizer regression driver.
    wiki-sync-contract =
      pkgs.runCommand "wiki-sync-contract"
        {
          nativeBuildInputs = [
            pkgs.bash
            pkgs.coreutils
            pkgs.findutils
            pkgs.gitMinimal
            pkgs.gnugrep
          ];
        }
        ''
          bash ${../tests/wiki-sync.sh} \
            ${../scripts/sync-server-wiki.sh} \
            ${self.packages.${system}.host-docs} \
            ${wikiSyncWrongOutputName} \
            ${wikiSyncMismatchedReport} \
            ${wikiSyncNoncanonicalReport} \
            ${wikiSyncChainedReport} \
            ${wikiSyncEscapingReport} \
            ${wikiSyncRelativeReport} \
            ${wikiSyncLineBreakReport}
          touch "$out"
        '';
  };
}
