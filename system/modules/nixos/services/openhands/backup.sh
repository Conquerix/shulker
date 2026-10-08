#!/usr/bin/env bash
# Stop the selected writer briefly; publish a private archive only after restart succeeds.
set -euo pipefail
unit=$1
archive=$2
shift 2
umask 077
mkdir -p "$(dirname "$archive")"
exec 9>"$archive.lock"
flock -n 9 || {
	echo 'OpenHands backup already running' >&2
	exit 1
}
pending=$(mktemp "$(dirname "$archive")/.pending-XXXXXXXX")
recover=0
cleanup() {
	status=$?
	if [ "$recover" = 1 ]; then
		systemctl start "$unit" || {
			echo 'OpenHands writer recovery failed; operator action required' >&2
			status=1
		}
	fi
	rm -f -- "$pending"
	exit "$status"
}
trap cleanup EXIT
if systemctl is-active --quiet "$unit"; then
	# A timed-out stop can still have taken effect; cleanup must attempt recovery.
	recover=1
	systemctl stop "$unit"
fi
args=()
for directory in "$@"; do
	[ -d "$directory" ] || {
		echo 'OpenHands backup source unavailable' >&2
		exit 1
	}
	args+=(-C "$(dirname "$directory")" "$(basename "$directory")")
done
# Do not dereference project symlinks into unrelated host data.
tar -czf "$pending" "${args[@]}"
if [ "$recover" = 1 ]; then
	systemctl start "$unit"
	recover=0
fi
mv -- "$pending" "$archive"
