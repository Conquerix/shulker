#!/usr/bin/env bash
# Serialize startup, shutdown and consistent snapshots of all KitchenOwl data.
set -euo pipefail
action="$1" state_dir="$2" dataset="$3" lock_file="$4" compose="$5" validate="$6"
exec 9>"$lock_file"
flock -w 900 9
snapshot="$dataset@borgmatic"
remove_snapshot() {
	if zfs list -H -o name -t snapshot "$1" >/dev/null 2>&1; then
		zfs destroy "$1"
	fi
}
case "$action" in
start)
	"$validate"
	"$compose" config --quiet
	"$compose" stop server
	if [ -f "$state_dir/data/database.db" ]; then
		remove_snapshot "$dataset@before-start"
		zfs snapshot "$dataset@before-start"
	fi
	"$compose" up --detach --wait --wait-timeout 180
	;;
stop)
	"$compose" down --timeout 60
	;;
backup)
	"$validate"
	if [ "$("$compose" ps --status running --services)" != server ]; then
		echo 'KitchenOwl is not running; refusing to archive stale data' >&2
		exit 65
	fi
	remove_snapshot "$snapshot"
	restart_needed=0
	snapshot_created=0
	recover() {
		status=$?
		trap - EXIT INT TERM
		if [ "$restart_needed" -eq 1 ]; then
			"$compose" up --detach --wait --wait-timeout 180 || status=1
		fi
		if [ "$status" -ne 0 ] && [ "$snapshot_created" -eq 1 ]; then
			zfs destroy "$snapshot" || true
		fi
		exit "$status"
	}
	trap recover EXIT
	trap 'exit 1' INT TERM
	restart_needed=1
	"$compose" stop server
	zfs snapshot "$snapshot"
	snapshot_created=1
	"$compose" up --detach --wait --wait-timeout 180
	restart_needed=0
	trap - EXIT INT TERM
	;;
cleanup)
	remove_snapshot "$snapshot"
	;;
*)
	echo 'Usage: kitchenowl-runtime start|stop|backup|cleanup' >&2
	exit 64
	;;
esac
