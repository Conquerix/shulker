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
	local first_subject="$3"
	local first_email="$4"
	local second_subject="$5"
	local second_email="$6"

	install -m 0600 /dev/null "$path"
	jq --null-input \
		--arg native_email "$native_email" \
		--arg first_subject "$first_subject" \
		--arg first_email "$first_email" \
		--arg second_subject "$second_subject" \
		--arg second_email "$second_email" \
		'{
            native: {email: $native_email},
            oauth: [
                {subject: $first_subject, email: $first_email},
                {subject: $second_subject, email: $second_email}
            ]
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

valid="$fixture_root/valid.json"
write_fixture \
	"$valid" \
	'native@breakglass.fixture.invalid' \
	'subject-one@immutable.fixture.invalid' \
	'first@oauth.fixture.invalid' \
	'subject-two@immutable.fixture.invalid' \
	'second@oauth.fixture.invalid'
expect_accept "$valid"

stdin_stdout="$fixture_root/stdin-stdout"
stdin_stderr="$fixture_root/stdin-stderr"
"$BASH" "$validator" - <"$valid" >"$stdin_stdout" 2>"$stdin_stderr"
test ! -s "$stdin_stdout"
test ! -s "$stdin_stderr"

subject_collision="$fixture_root/subject-collision.json"
write_fixture \
	"$subject_collision" \
	'subject-one@immutable.fixture.invalid' \
	'subject-one@immutable.fixture.invalid' \
	'first@oauth.fixture.invalid' \
	'subject-two@immutable.fixture.invalid' \
	'second@oauth.fixture.invalid'
expect_reject "$subject_collision"

email_collision="$fixture_root/email-collision.json"
write_fixture \
	"$email_collision" \
	'FIRST@OAUTH.FIXTURE.INVALID' \
	'subject-one@immutable.fixture.invalid' \
	'first@oauth.fixture.invalid' \
	'subject-two@immutable.fixture.invalid' \
	'second@oauth.fixture.invalid'
expect_reject "$email_collision"

oauth_collision="$fixture_root/oauth-collision.json"
write_fixture \
	"$oauth_collision" \
	'native@breakglass.fixture.invalid' \
	'subject-one@immutable.fixture.invalid' \
	'first@oauth.fixture.invalid' \
	'subject-one@immutable.fixture.invalid' \
	'second@oauth.fixture.invalid'
expect_reject "$oauth_collision"

malformed_email="$fixture_root/malformed-email.json"
write_fixture \
	"$malformed_email" \
	'not-an-email' \
	'subject-one@immutable.fixture.invalid' \
	'first@oauth.fixture.invalid' \
	'subject-two@immutable.fixture.invalid' \
	'second@oauth.fixture.invalid'
expect_reject "$malformed_email"

chmod 0644 "$valid"
expect_reject "$valid"
