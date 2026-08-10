#!/usr/bin/env bash

set -euo pipefail

fail_identity() {
	echo "Seafile identity validation failed" >&2
	exit 65
}

if [ "$#" -ne 1 ]; then
	echo "usage: validate-seafile-identities.sh FILE|-" >&2
	exit 64
fi

source_path="$1"
temporary=""
cleanup() {
	[ -z "$temporary" ] || rm -f -- "$temporary"
}
trap cleanup EXIT

if [ "$source_path" = - ]; then
	temporary="$(mktemp)"
	chmod 0600 "$temporary"
	cat >"$temporary"
	source_path="$temporary"
else
	[ -f "$source_path" ] && [ ! -L "$source_path" ] || fail_identity
	[ "$(stat -c %u -- "$source_path")" -eq "$(id -u)" ] || fail_identity
	mode="$(stat -c %a -- "$source_path")"
	[ "$mode" = 400 ] || [ "$mode" = 600 ] || fail_identity
	[ "$(stat -c %h -- "$source_path")" -eq 1 ] || fail_identity
fi

jq --exit-status '
    def valid_email:
        type == "string" and
        test("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$");
    type == "object" and
    ((keys | sort) == ["native", "oauth"]) and
    (.native | type == "object" and keys == ["email"]) and
    (.native.email | valid_email) and
    (.oauth | type == "array" and length == 2) and
    all(.oauth[];
        type == "object" and
        ((keys | sort) == ["email", "subject"]) and
        (.subject | type == "string" and length > 0) and
        (.email | valid_email)
    ) and
    (
        [
            (.native.email | ascii_downcase),
            (.oauth[0].subject | ascii_downcase),
            (.oauth[0].email | ascii_downcase),
            (.oauth[1].subject | ascii_downcase),
            (.oauth[1].email | ascii_downcase)
        ] as $identities |
        ($identities | length) == ($identities | unique | length)
    )
' "$source_path" >/dev/null 2>&1 || fail_identity
