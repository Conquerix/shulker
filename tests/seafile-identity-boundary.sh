#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -ne 1 ]; then
	echo "usage: seafile-identity-boundary.sh VALIDATOR" >&2
	exit 64
fi

validator="$1"
fixture_root="$(mktemp -d)"
trap 'rm -rf -- "$fixture_root"' EXIT

write_fixture() {
	local path="$1"
	local native_email="$2"
	local oauth="$3"

	install -m 0600 /dev/null "$path"
	jq --null-input \
		--arg native_email "$native_email" \
		--argjson oauth "$oauth" \
		'{
            native: {email: $native_email},
            oauth: $oauth
        }' >"$path"
}

expect_accept() {
	local source="$1"
	local stdout="$fixture_root/stdout"
	local stderr="$fixture_root/stderr"

	: >"$stdout"
	: >"$stderr"
	"$BASH" "$validator" "$source" >"$stdout" 2>"$stderr"
	test ! -s "$stdout"
	test ! -s "$stderr"
}

expect_reject() {
	local source="$1"
	local stdout="$fixture_root/stdout"
	local stderr="$fixture_root/stderr"

	: >"$stdout"
	: >"$stderr"
	if "$BASH" "$validator" "$source" >"$stdout" 2>"$stderr"; then
		echo "Seafile identity validator accepted an invalid boundary" >&2
		exit 1
	fi
	test ! -s "$stdout"
	! grep -F 'fixture.invalid' "$stderr"
}

valid_one="$fixture_root/valid-one.json"
write_fixture \
	"$valid_one" \
	'native@breakglass.fixture.invalid' \
	'[{"subject":"subject-one@immutable.fixture.invalid","email":"first@oauth.fixture.invalid"}]'
expect_accept "$valid_one"

valid_two="$fixture_root/valid-two.json"
write_fixture \
	"$valid_two" \
	'native@breakglass.fixture.invalid' \
	'[
        {"subject":"subject-one@immutable.fixture.invalid","email":"first@oauth.fixture.invalid"},
        {"subject":"subject-two@immutable.fixture.invalid","email":"second@oauth.fixture.invalid"}
    ]'
expect_accept "$valid_two"

zero_oauth="$fixture_root/zero-oauth.json"
write_fixture \
	"$zero_oauth" \
	'native@breakglass.fixture.invalid' \
	'[]'
expect_reject "$zero_oauth"

three_oauth="$fixture_root/three-oauth.json"
write_fixture \
	"$three_oauth" \
	'native@breakglass.fixture.invalid' \
	'[
        {"subject":"subject-one@immutable.fixture.invalid","email":"first@oauth.fixture.invalid"},
        {"subject":"subject-two@immutable.fixture.invalid","email":"second@oauth.fixture.invalid"},
        {"subject":"subject-three@immutable.fixture.invalid","email":"third@oauth.fixture.invalid"}
    ]'
expect_reject "$three_oauth"

stdin_stdout="$fixture_root/stdin-stdout"
stdin_stderr="$fixture_root/stdin-stderr"
"$BASH" "$validator" - <"$valid_two" >"$stdin_stdout" 2>"$stdin_stderr"
test ! -s "$stdin_stdout"
test ! -s "$stdin_stderr"

subject_collision="$fixture_root/subject-collision.json"
write_fixture \
	"$subject_collision" \
	'subject-one@immutable.fixture.invalid' \
	'[
        {"subject":"subject-one@immutable.fixture.invalid","email":"first@oauth.fixture.invalid"},
        {"subject":"subject-two@immutable.fixture.invalid","email":"second@oauth.fixture.invalid"}
    ]'
expect_reject "$subject_collision"

email_collision="$fixture_root/email-collision.json"
write_fixture \
	"$email_collision" \
	'FIRST@OAUTH.FIXTURE.INVALID' \
	'[
        {"subject":"subject-one@immutable.fixture.invalid","email":"first@oauth.fixture.invalid"},
        {"subject":"subject-two@immutable.fixture.invalid","email":"second@oauth.fixture.invalid"}
    ]'
expect_reject "$email_collision"

oauth_collision="$fixture_root/oauth-collision.json"
write_fixture \
	"$oauth_collision" \
	'native@breakglass.fixture.invalid' \
	'[
        {"subject":"subject-one@immutable.fixture.invalid","email":"first@oauth.fixture.invalid"},
        {"subject":"subject-one@immutable.fixture.invalid","email":"second@oauth.fixture.invalid"}
    ]'
expect_reject "$oauth_collision"

malformed_email="$fixture_root/malformed-email.json"
write_fixture \
	"$malformed_email" \
	'not-an-email' \
	'[
        {"subject":"subject-one@immutable.fixture.invalid","email":"first@oauth.fixture.invalid"},
        {"subject":"subject-two@immutable.fixture.invalid","email":"second@oauth.fixture.invalid"}
    ]'
expect_reject "$malformed_email"

chmod 0644 "$valid_two"
expect_reject "$valid_two"
