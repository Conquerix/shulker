#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
	echo "usage: $0 SHULKER_REBUILD" >&2
	exit 64
fi

rebuild="$1"
fixture_root="$TMPDIR/shulker-rebuild-secret-preflight"
stub_dir="$fixture_root/bin"
token_file="$fixture_root/opnix-token"
resolved_record="$fixture_root/resolved-path"
opnix_marker="$fixture_root/opnix-called"
rebuild_marker="$fixture_root/rebuild-called"

mkdir -p "$stub_dir"
printf '%s\n' synthetic-token >"$token_file"

cat >"$stub_dir/nix" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
jq -n --arg token "${STUB_TOKEN_FILE:?}" '
  {
    opnix: {
      enabled: true,
      tokenFile: $token,
      configFiles: [],
      secrets: [{
        path: "seafileEnv",
        reference: "op://Shulker/fixture/Seafile/Environment",
        owner: "",
        group: "",
        mode: "0600",
        services: []
      }]
    },
    schemas: {
      seafileEnv: {
        format: "dotenv",
        exactKeys: {
          INIT_SEAFILE_MYSQL_ROOT_PASSWORD: { minLength: 32, pattern: "^[A-Za-z0-9._~!@%+,/:=-]+$" },
          SEAFILE_MYSQL_DB_PASSWORD: { minLength: 32, pattern: "^[A-Za-z0-9._~!@+,/:=-]+$" },
          REDIS_PASSWORD: { minLength: 32, pattern: "^[A-Za-z0-9._~!@%+,/:=-]+$" },
          JWT_PRIVATE_KEY: { minLength: 32, pattern: "^[A-Za-z0-9._~!@%+,/:=-]+$" },
          SEAHUB_SECRET_KEY: { minLength: 50, pattern: "^[A-Za-z0-9._~!@%+,/:=-]+$" },
          INIT_SEAFILE_ADMIN_EMAIL: { minLength: 1, pattern: "^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$" },
          INIT_SEAFILE_ADMIN_PASSWORD: { minLength: 32, pattern: "^[A-Za-z0-9._~!@%+,/:=-]+$" },
          INIT_SS_ADMIN_USER: { minLength: 1, pattern: "^[A-Za-z0-9._~!@%+,/:=-]+$" },
          INIT_SS_ADMIN_PASSWORD: { minLength: 32, pattern: "^[A-Za-z0-9._~!@%+,/:=-]+$" },
          SEAFILE_OAUTH_CLIENT_ID: { minLength: 1, pattern: "^[A-Za-z0-9._~!@%+,/:=-]+$" },
          SEAFILE_OAUTH_CLIENT_SECRET: { minLength: 32, pattern: "^[A-Za-z0-9._~!@%+,/:=-]+$" },
          ONLYOFFICE_JWT_SECRET: { minLength: 32, pattern: "^[A-Za-z0-9._~!@%+,/:=-]+$" }
        }
      }
    }
  }
'
EOF

cat >"$stub_dir/opnix" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
output_dir=""
while [ "$#" -gt 0 ]; do
	case "$1" in
	-output)
		output_dir="$2"
		shift 2
		;;
	*) shift ;;
	esac
done
[ -n "$output_dir" ]
mkdir -p "$output_dir"
resolved="$output_dir/seafileEnv"
install -m "${STUB_RESOLVED_MODE:-0400}" "${STUB_SECRET_INPUT:?}" "$resolved"
printf '%s\n' "$resolved" >"${STUB_RESOLVED_RECORD:?}"
: >"${STUB_OPNIX_MARKER:?}"
EOF

cat >"$stub_dir/nixos-rebuild" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
test -f "${STUB_OPNIX_MARKER:?}"
resolved="$(cat "${STUB_RESOLVED_RECORD:?}")"
if [ -e "$resolved" ] || [ -L "$resolved" ]; then
	echo "resolved secret tree still exists at rebuild execution" >&2
	exit 1
fi
: >"${STUB_REBUILD_MARKER:?}"
EOF

chmod +x "$stub_dir/nix" "$stub_dir/opnix" "$stub_dir/nixos-rebuild"

write_valid_environment() {
	cat >"$1" <<'EOF'
INIT_SEAFILE_MYSQL_ROOT_PASSWORD=RootPassword0123456789abcdef0123456789
SEAFILE_MYSQL_DB_PASSWORD=DatabasePassword0123456789abcdef0123
REDIS_PASSWORD=Allowed._~!@%+,/:=-Allowed._~!@%+,/:=-
JWT_PRIVATE_KEY=JwtPrivateKey0123456789abcdef012345678
SEAHUB_SECRET_KEY=SeahubSecretKey0123456789abcdef0123456789abcdef0123456789
INIT_SEAFILE_ADMIN_EMAIL=admin@example.invalid
INIT_SEAFILE_ADMIN_PASSWORD=AdminPassword0123456789abcdef01234567
INIT_SS_ADMIN_USER=seasearch-admin
INIT_SS_ADMIN_PASSWORD=SeaSearchPassword0123456789abcdef0123
SEAFILE_OAUTH_CLIENT_ID=seafile-client
SEAFILE_OAUTH_CLIENT_SECRET=OAuthSecret0123456789abcdef0123456789
ONLYOFFICE_JWT_SECRET=OnlyOfficeSecret0123456789abcdef012345
EOF
	chmod 0400 "$1"
}

assert_sanitized_output() {
	local input="$1"
	local output="$2"
	local value
	while IFS= read -r line || [ -n "$line" ]; do
		case "$line" in
		*=*) value="${line#*=}" ;;
		*) continue ;;
		esac
		if [ -n "$value" ] && grep -F -- "$value" "$output" >/dev/null; then
			echo "secret preflight output exposed a fixture value" >&2
			exit 1
		fi
	done <"$input"
	if grep -F -- 'op://' "$output" >/dev/null; then
		echo "secret preflight output exposed an OpNix reference" >&2
		exit 1
	fi
}

run_case() {
	local name="$1"
	local expectation="$2"
	local expected_key="${3:-}"
	local resolved_mode="${4:-0400}"
	local input="$fixture_root/$name.env"
	local output="$fixture_root/$name.output"
	local status=0

	rm -f "$resolved_record" "$opnix_marker" "$rebuild_marker"
	set +e
	env \
		SHULKER_NIX_COMMAND="$stub_dir/nix" \
		SHULKER_OPNIX_COMMAND="$stub_dir/opnix" \
		SHULKER_NIXOS_REBUILD_COMMAND="$stub_dir/nixos-rebuild" \
		STUB_TOKEN_FILE="$token_file" \
		STUB_SECRET_INPUT="$input" \
		STUB_RESOLVED_RECORD="$resolved_record" \
		STUB_OPNIX_MARKER="$opnix_marker" \
		STUB_REBUILD_MARKER="$rebuild_marker" \
		STUB_RESOLVED_MODE="$resolved_mode" \
		"$rebuild" switch --flake .#fixture >"$output" 2>&1
	status=$?
	set -e

	assert_sanitized_output "$input" "$output"
	if [ "$expectation" = success ]; then
		[ "$status" -eq 0 ] || {
			cat "$output" >&2
			exit 1
		}
		test -f "$rebuild_marker"
	else
		[ "$status" -ne 0 ] || {
			echo "$name unexpectedly reached nixos-rebuild" >&2
			exit 1
		}
		test ! -e "$rebuild_marker"
		grep -F -- seafileEnv "$output" >/dev/null
		[ -z "$expected_key" ] || grep -F -- "$expected_key" "$output" >/dev/null
	fi
}

valid="$fixture_root/valid.env"
write_valid_environment "$valid"
valid_copy="$fixture_root/valid.expected"
cp "$valid" "$valid_copy"
run_case valid success
cmp "$valid_copy" "$valid"

missing="$fixture_root/missing.env"
grep -v '^REDIS_PASSWORD=' "$valid" >"$missing"
chmod 0400 "$missing"
run_case missing failure REDIS_PASSWORD

empty="$fixture_root/empty.env"
sed 's/^JWT_PRIVATE_KEY=.*/JWT_PRIVATE_KEY=/' "$valid" >"$empty"
chmod 0400 "$empty"
run_case empty failure JWT_PRIVATE_KEY

duplicate="$fixture_root/duplicate.env"
cp "$valid" "$duplicate"
chmod 0600 "$duplicate"
grep '^REDIS_PASSWORD=' "$valid" >>"$duplicate"
chmod 0400 "$duplicate"
run_case duplicate failure REDIS_PASSWORD

unknown="$fixture_root/unknown.env"
cp "$valid" "$unknown"
chmod 0600 "$unknown"
printf '%s\n' 'FOREIGN_KEY=ForeignValue0123456789abcdef0123456789' >>"$unknown"
chmod 0400 "$unknown"
run_case unknown failure FOREIGN_KEY

malformed="$fixture_root/malformed.env"
cp "$valid" "$malformed"
chmod 0600 "$malformed"
printf '%s\n' 'this record has no separator' >>"$malformed"
chmod 0400 "$malformed"
run_case malformed failure

invalid_key="$fixture_root/invalid-key.env"
sed 's/^REDIS_PASSWORD=/BAD-KEY=/' "$valid" >"$invalid_key"
chmod 0400 "$invalid_key"
run_case invalid-key failure BAD-KEY

nul_key="$fixture_root/nul-key.env"
grep -v '^REDIS_PASSWORD=' "$valid" >"$nul_key"
printf 'REDIS\000_PASSWORD=Allowed._~!@%%+,/:=-Allowed._~!@%%+,/:=-\n' >>"$nul_key"
chmod 0400 "$nul_key"
run_case nul-key failure

nul_value="$fixture_root/nul-value.env"
grep -v '^JWT_PRIVATE_KEY=' "$valid" >"$nul_value"
printf 'JWT_PRIVATE_KEY=JwtPrivateKey012345\0006789abcdef012345678\n' >>"$nul_value"
chmod 0400 "$nul_value"
run_case nul-value failure

invalid_email="$fixture_root/invalid-email.env"
sed 's/^INIT_SEAFILE_ADMIN_EMAIL=.*/INIT_SEAFILE_ADMIN_EMAIL=not-an-email/' "$valid" >"$invalid_email"
chmod 0400 "$invalid_email"
run_case invalid-email failure INIT_SEAFILE_ADMIN_EMAIL

short="$fixture_root/short.env"
sed 's/^ONLYOFFICE_JWT_SECRET=.*/ONLYOFFICE_JWT_SECRET=too-short/' "$valid" >"$short"
chmod 0400 "$short"
run_case short failure ONLYOFFICE_JWT_SECRET

mysql_percent="$fixture_root/mysql-percent.env"
sed 's/^SEAFILE_MYSQL_DB_PASSWORD=.*/SEAFILE_MYSQL_DB_PASSWORD=Database%Password0123456789abcdef0123/' "$valid" >"$mysql_percent"
chmod 0400 "$mysql_percent"
run_case mysql-percent failure SEAFILE_MYSQL_DB_PASSWORD

unsafe_mode="$fixture_root/unsafe-mode.env"
cp "$valid" "$unsafe_mode"
chmod 0644 "$unsafe_mode"
run_case unsafe-mode failure seafileEnv 0644

echo "Checked rebuild structured-secret preflight contract passed"
