# Keep Seafile reports, runbooks, and release monitoring consistent and public-safe.
{
  self,
  system,
  pkgs,
  ...
}:

let
  wardenServerDocs = self.packages.${system}."server-docs-warden";
  infrastructureData = self.packages.${system}.infrastructure-data;
  infrastructureDiagram = self.packages.${system}.infrastructure-diagram;
  wikiDocs = self.packages.${system}.wiki-docs;
in
{
  seafile-docs-contract =
    pkgs.runCommand "seafile-docs-contract"
      {
        nativeBuildInputs = [
          pkgs.gawk
          pkgs.gnugrep
          pkgs.jq
        ];
      }
      ''
        combined="$TMPDIR/seafile-generated-docs"
        seafile_runbook=${wikiDocs}/Service-Seafile.md
        seafile_runbook_text="$TMPDIR/seafile-runbook-text"
        seafile_service_row="$TMPDIR/seafile-service-row"
        seafile_operations="$TMPDIR/seafile-operations"
        seafile_operations_text="$TMPDIR/seafile-operations-text"
        mkdir -p "$combined/warden" "$combined/infrastructure" "$combined/diagram" "$combined/wiki"
        cp -R ${wardenServerDocs}/. "$combined/warden"
        cp -R ${infrastructureData}/. "$combined/infrastructure"
        cp -R ${infrastructureDiagram}/. "$combined/diagram"
        cp -R ${wikiDocs}/. "$combined/wiki"

        warden_report="$combined/warden/warden.md"
        inventory="$combined/infrastructure/infrastructure.json"
        diagram="$combined/diagram/Infrastructure.md"
        wiki_services="$combined/wiki/Services.md"
        test -f "$warden_report"
        test -f "$inventory"
        test -f "$diagram"
        test -f "$wiki_services"
        test -f "$combined/wiki/Fleet.md"
        test -f "$combined/wiki/Public-Services.md"
        test -f "$seafile_runbook"
        test -s "$seafile_runbook"
        tr '\n' ' ' < "$seafile_runbook" > "$seafile_runbook_text"

        grep -F -- '| Seafile Pro 13.0.25 |' "$warden_report" > "$seafile_service_row"
        test "$(wc -l < "$seafile_service_row")" -eq 1

        awk '
          $0 == "Inspect Seafile Pro and run its bounded operator checks:" { in_section = 1 }
          $0 == "Roll back the active system profile:" { in_section = 0 }
          in_section { print }
        ' "$warden_report" > "$seafile_operations"
        test -s "$seafile_operations"
        tr '\n' ' ' < "$seafile_operations" > "$seafile_operations_text"

        for staged_identity_policy in \
          'Initial owner-only OAuth enrollment' \
          'one native plus one OAuth user initially' \
          'one native plus two OAuth users after second-user enrollment' \
          'no OIDC secret rotation or 1Password edit during second-user enrollment'
        do
          grep -F -- "$staged_identity_policy" "$seafile_runbook_text" >/dev/null
          grep -F -- "$staged_identity_policy" "$seafile_service_row" >/dev/null
          grep -F -- "$staged_identity_policy" "$seafile_operations_text" >/dev/null
        done

        for stale_identity_policy in \
          'containing the two intended people' \
          'The two OAuth users plus the native administrator consume' \
          'Before making Seafile authoritative, test both users'
        do
          if grep -R -F -- "$stale_identity_policy" "$seafile_runbook" "$warden_report" >/dev/null; then
            echo "Seafile documentation contains stale identity guidance: $stale_identity_policy" >&2
            exit 1
          fi
        done

        for container in \
          seafile \
          seafile-mariadb \
          seafile-redis \
          seafile-seasearch \
          seafile-notification \
          seafile-metadata \
          seafile-onlyoffice
        do
          test "$(grep -F -c -- "| $container |" "$warden_report")" -eq 1
        done

        test "$(grep -E -o '@sha256:[0-9a-f]{64}' "$seafile_runbook" | wc -l)" -eq 7

        for expected in \
          'Seafile Pro 13.0.25' \
          'https://files.shulker.link' \
          'https://office.shulker.link' \
          '127.0.0.1:23239' \
          '127.0.0.1:23240' \
          '127.0.0.1:23241' \
          'flash_pool/flash/storage/seafile' \
          '1.5 TiB' \
          '3 named users maximum' \
          'Pocket ID OIDC' \
          'SeaSearch' \
          'Notification' \
          'Metadata' \
          'OnlyOffice' \
          'Borgmatic' \
          '/storage/flash/seafile/.zfs/snapshot/borgmatic/shared' \
          '/storage/flash/seafile/.zfs/snapshot/borgmatic/backups'
        do
          grep -R -F -- "$expected" "$combined" >/dev/null
        done

        for secret_name in \
          INIT_SEAFILE_MYSQL_ROOT_PASSWORD \
          SEAFILE_MYSQL_DB_PASSWORD \
          REDIS_PASSWORD \
          JWT_PRIVATE_KEY \
          SEAHUB_SECRET_KEY \
          INIT_SEAFILE_ADMIN_EMAIL \
          INIT_SEAFILE_ADMIN_PASSWORD \
          INIT_SS_ADMIN_USER \
          INIT_SS_ADMIN_PASSWORD \
          SEAFILE_OAUTH_CLIENT_ID \
          SEAFILE_OAUTH_CLIENT_SECRET \
          ONLYOFFICE_JWT_SECRET
        do
          grep -F -- "$secret_name" "$seafile_runbook" >/dev/null
        done

        for command in \
          seafile-health-check \
          seafile-extended-health \
          seafile-fsck-shallow \
          seafile-fsck-full \
          seafile-gc-dry-run \
          seafile-search-status \
          seafile-search-update \
          seafile-search-rebuild \
          seafile-metadata-probe \
          seafile-onlyoffice-smoke-test \
          seafile-backup-status \
          seafile-pre-upgrade-check \
          seafile-restore-prepare \
          seafile-restore-verify \
          seafile-restore-teardown \
          'borgmatic create' \
          'borgmatic check'
        do
          grep -F -- "$command" "$seafile_runbook" >/dev/null
          grep -F -- "$command" "$seafile_operations" >/dev/null
        done

        for policy in \
          'Repository implementation and commits do not deploy Seafile' \
          'authoritative family file service' \
          'Immich is the sole authoritative store' \
          'no documented server-side switch that enforces this preference' \
          'They do not extract archive data or automate browser login'
        do
          grep -F -- "$policy" "$seafile_runbook_text" >/dev/null
        done

        jq -e '
          . as $root
          | ($root.schema == 2)
          and all(
            $root.hosts[];
            . as $host
            | (([$host.services[].key] | length) == ([$host.services[].key] | unique | length))
            and all(
              $host.dependencies[]?;
              .from as $from
              | .to as $to
              | (([$host.services[].key] | index($from)) != null)
              and (([$host.services[].key] | index($to)) != null)
            )
          )
          and (
            ($root.hosts[] | select(.name == "warden")) as $warden
            | (([
                $warden.services[]
                | select(.key | startswith("seafile"))
                | .key
              ] | sort) == [
                "seafile",
                "seafile-mariadb",
                "seafile-metadata",
                "seafile-notification",
                "seafile-onlyoffice",
                "seafile-redis",
                "seafile-seasearch"
              ])
            and all(
              $warden.services[] | select(.key | startswith("seafile"));
              if .key == "seafile" then
                .endpoint == "https://files.shulker.link"
              elif .key == "seafile-onlyoffice" then
                .endpoint == "https://office.shulker.link"
              else
                .endpoint == null
              end
            )
            and (([
                $warden.dependencies[]
                | select((.from | startswith("seafile")) or (.to | startswith("seafile")))
                | "\(.from)|\(.to)|\(.relation)"
              ] | sort) == ([
                "seafile|backup|writer-quiesced backup",
                "seafile|seafile-mariadb|application metadata",
                "seafile|seafile-metadata|extended metadata",
                "seafile|seafile-notification|real-time notifications",
                "seafile|seafile-onlyoffice|browser Office editing",
                "seafile|seafile-redis|cache and coordination",
                "seafile|seafile-seasearch|full-text search",
                "seafile-metadata|seafile-mariadb|file metadata",
                "seafile-metadata|seafile-redis|cache and event queue",
                "seafile-metadata|seafile|shared object and configuration state",
                "seafile-notification|seafile-mariadb|notification database",
                "seafile-notification|seafile|application events"
              ] | sort))
            and any(
              $warden.connections[];
              .from == "seafile"
              and .to == "https://sso.shulker.link"
              and .relation == "OIDC authentication"
            )
          )
        ' "$inventory" >/dev/null

        grep -F -- '## Local component dependencies' "$diagram" >/dev/null
        grep -F -- 'warden local components' "$diagram" >/dev/null
        grep -F -- '## Management dependencies' "$diagram" >/dev/null
        grep -F -- '## Public access' "$diagram" >/dev/null
        grep -F -- '## Local component dependencies' "$wiki_services" >/dev/null

        unexpected_loopback="$({
          grep -E -o '127\.0\.0\.1:[0-9]+' "$seafile_runbook" || true
        } | grep -E -v '^127\.0\.0\.1:(23239|23240|23241)$' || true)"
        if test -n "$unexpected_loopback"; then
          echo "Seafile runbook contains an undeclared private target" >&2
          exit 1
        fi

        if grep -R -E \
          '(INIT_SEAFILE_MYSQL_ROOT_PASSWORD|SEAFILE_MYSQL_DB_PASSWORD|REDIS_PASSWORD|JWT_PRIVATE_KEY|SEAHUB_SECRET_KEY|INIT_SEAFILE_ADMIN_EMAIL|INIT_SEAFILE_ADMIN_PASSWORD|INIT_SS_ADMIN_USER|INIT_SS_ADMIN_PASSWORD|SEAFILE_OAUTH_CLIENT_ID|SEAFILE_OAUTH_CLIENT_SECRET|ONLYOFFICE_JWT_SECRET)[[:space:]]*=' \
          "$combined" >/dev/null
        then
          echo "Generated Seafile documentation contains a secret value assignment" >&2
          exit 1
        fi

        if grep -R -E \
          'op://|/run/seafile|[[:alnum:]._%+-]+@[[:alnum:].-]+\.[[:alpha:]]{2,}|share[_ -]?token[[:space:]]*[:=]|document[_ -]?filename[[:space:]]*[:=]|"(targets?|accessPolicies|identities|credentials)"[[:space:]]*:' \
          "$combined" >/dev/null
        then
          echo "Generated Seafile documentation contains private runtime or account material" >&2
          exit 1
        fi

        for unsupported in \
          'Nix proves live Pangolin' \
          'Nix proves Pangolin routing' \
          'Metadata has a manual consistency command' \
          'server enforces camera upload disabled' \
          'server disables camera upload' \
          'forcesave captures every edit' \
          'forcesave preserves every edit' \
          "every forced save appears in OnlyOffice's own history"
        do
          if grep -R -F -- "$unsupported" "$combined" >/dev/null; then
            echo "Seafile documentation contains an unsupported claim: $unsupported" >&2
            exit 1
          fi
        done

        if grep -R -F -- 'seafile-release-monitor' "$combined" >/dev/null; then
          echo "Seafile release-monitor documentation landed before its workflow" >&2
          exit 1
        fi

        touch "$out"
      '';

  # Source contracts constrain issue ownership, release lines, and workflow permissions.
  seafile-release-workflow-contract =
    pkgs.runCommand "seafile-release-workflow-contract"
      {
        nativeBuildInputs = [
          pkgs.gawk
          pkgs.gnugrep
        ];
      }
      ''
        workflow=${../.}/.github/workflows/check-seafile-release.yml
        check_workflow=${../.}/.github/workflows/check.yml
        update_workflow=${../.}/.github/workflows/update-flake.yml
        root_readme=${../README.md}
        github_readme=${../.github/AUTOMATION.md}
        wiki_automation_source=${../lib/wiki-docs.nix}
        wiki_automation=${wikiDocs}/Automation.md

        test -f "$workflow"

        test "$(grep -F -c -- 'workflow_dispatch:' "$workflow")" -eq 1
        test "$(grep -F -c -- 'cron: "43 5 * * 1"' "$workflow")" -eq 1

        concurrency="$TMPDIR/seafile-release-concurrency"
        awk '
          $0 == "concurrency:" { in_block = 1; next }
          $0 == "permissions:" { in_block = 0 }
          in_block && NF { print }
        ' "$workflow" > "$concurrency"
        test "$(wc -l < "$concurrency")" -eq 2
        grep -F -x -- '  group: seafile-release-monitor' "$concurrency" >/dev/null
        grep -F -x -- '  cancel-in-progress: false' "$concurrency" >/dev/null

        permissions="$TMPDIR/seafile-release-permissions"
        awk '
          $0 == "permissions:" { in_block = 1; next }
          $0 == "jobs:" { in_block = 0 }
          in_block && NF { print }
        ' "$workflow" > "$permissions"
        test "$(wc -l < "$permissions")" -eq 2
        grep -F -x -- '  contents: read' "$permissions" >/dev/null
        grep -F -x -- '  issues: write' "$permissions" >/dev/null

        test "$(grep -E -c '^[[:space:]]*- uses:' "$workflow")" -eq 2
        test "$(grep -E -c '^[[:space:]]*- uses: [^@]+@[0-9a-f]{40}( # .*)?$' "$workflow")" -eq 2
        grep -F -- \
          'actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2' \
          "$workflow" >/dev/null
        grep -F -- \
          'cachix/install-nix-action@630ae543ea3a38a9a4166f03376c02c50f408342 # v31.11.0' \
          "$workflow" >/dev/null

        test "$(grep -F -c -- 'nix eval --json' "$workflow")" -eq 1
        test "$(grep -F -c -- '.#nixosConfigurations.warden.config.shulker.system.modules.seafile.releaseVersions' "$workflow")" -eq 1
        grep -F -- \
          'components=(seafile mariadb redis seasearch notification metadata onlyoffice)' \
          "$workflow" >/dev/null
        grep -F -- 'https://hub.docker.com/v2/repositories/$repository/tags' "$workflow" >/dev/null
        grep -F -- 'for component in "''${components[@]}"' "$workflow" >/dev/null
        grep -F -- 'configured[$component]' "$workflow" >/dev/null
        grep -F -- 'detected_tags[$component]' "$workflow" >/dev/null

        for expected in \
          "[seafile]='seafileltd/seafile-pro-mc'" \
          "[mariadb]='library/mariadb'" \
          "[redis]='library/redis'" \
          "[seasearch]='seafileltd/seasearch'" \
          "[notification]='seafileltd/notification-server'" \
          "[metadata]='seafileltd/seafile-md-server'" \
          "[onlyoffice]='onlyoffice/documentserver'" \
          "[seafile]='^13[.]0[.][0-9]+$'" \
          "[mariadb]='^10[.]11[.][0-9]+$'" \
          "[redis]='^7[.]4[.][0-9]+-alpine$'" \
          "[seasearch]='^1[.]0[.][0-9]+$'" \
          "[notification]='^13[.]0[.][0-9]+$'" \
          "[metadata]='^13[.]0[.][0-9]+$'" \
          "[onlyoffice]='^9[.]4[.][0-9]+[.][0-9]+$'"
        do
          grep -F -- "$expected" "$workflow" >/dev/null
        done

        test "$(grep -F -c -- '<!-- seafile-release-monitor -->' "$workflow")" -eq 1
        test "$(grep -F -c -- 'chore: review Seafile stack updates' "$workflow")" -eq 1
        for expected in \
          'gh issue list --state open' \
          'select(.title == \"$issue_title\")' \
          'if grep -F -- "$marker" <<<"$issue_body"' \
          'gh issue edit "$managed_issue"' \
          'gh issue create --title "$issue_title"'
        do
          grep -F -- "$expected" "$workflow" >/dev/null
        done

        for expected in \
          'Check Seafile stack releases' \
          'weekly or manual' \
          'non-deploying'
        do
          grep -F -i -- "$expected" "$wiki_automation_source" >/dev/null
          grep -F -i -- "$expected" "$wiki_automation" >/dev/null
        done
        grep -F -- \
          '[Automation](https://github.com/Conquerix/shulker/wiki/Automation)' \
          "$root_readme" >/dev/null
        for expected in \
          'every Monday and on demand' \
          'contents: read' \
          'issues: write' \
          'official Docker Hub tag API' \
          '<!-- seafile-release-monitor -->' \
          'similarly titled human-authored issue is never changed' \
          'never edits image pins' \
          'mutates a host'
        do
          grep -F -i -- "$expected" "$github_readme" >/dev/null
        done

        suite_command='nix build --no-link .#checks.x86_64-linux.seafile-contract-suite'
        grep -F -- "$suite_command" "$check_workflow" >/dev/null
        grep -F -- "$suite_command" "$update_workflow" >/dev/null

        for forbidden in \
          'contents: write' \
          'pull-requests: write' \
          'git add' \
          'git apply' \
          'git checkout' \
          'git commit' \
          'git push' \
          'git switch' \
          'nixos-rebuild' \
          'ssh ' \
          'op://' \
          '1password' \
          'pocket id' \
          'pangolin'
        do
          if grep -F -i -- "$forbidden" "$workflow" >/dev/null; then
            echo "Seafile release monitor contains forbidden access or mutation: $forbidden" >&2
            exit 1
          fi
        done

        touch "$out"
      '';
}
