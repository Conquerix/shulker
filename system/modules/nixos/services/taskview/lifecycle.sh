#!/usr/bin/env bash
# All state-changing maintenance shares this lock. Failed migrations leave writers stopped.
set -euo pipefail
action="$1" state_dir="$2" lock_file="$3" compose="$4" validate="$5" backup="$6" health="$7"
exec 9>"$lock_file"
flock -w 900 9
case "$action" in
start)
	"$validate"
	"$compose" config --quiet
	"$compose" stop api mcp
	"$compose" up --detach --wait --wait-timeout 180 database
	# Every established startup takes a fresh portable backup before schema changes.
	if [ -f "$state_dir/postgres/PG_VERSION" ]; then
		TASKVIEW_MAINTENANCE_LOCK_HELD=1 "$backup"
	fi
	# Never restart writers on a migration failure, including TERM/INT.
	cleanup_failed_start() {
		status=$?
		trap - EXIT INT TERM
		if [ "$status" -ne 0 ]; then
			"$compose" stop api mcp >/dev/null 2>&1 || true
		fi
		exit "$status"
	}
	trap cleanup_failed_start EXIT
	trap 'exit 1' INT TERM
	"$compose" run --rm --no-deps migration
	"$compose" up --detach --force-recreate --no-deps --wait --wait-timeout 180 centrifugo api web mcp
	"$health"
	trap - EXIT INT TERM
	;;
stop)
	"$compose" down --timeout 60
	;;
*)
	echo 'Usage: taskview lifecycle start|stop' >&2
	exit 64
	;;
esac
