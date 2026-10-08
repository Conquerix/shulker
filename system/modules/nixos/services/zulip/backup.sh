#!/usr/bin/env bash
# Freeze application writers while exporting PostgreSQL and uploads together.
set -euo pipefail
state=$1
compose=$2
[ -d "$state/data" ] || {
	echo 'Zulip state unavailable' >&2
	exit 1
}
mkdir -p "$state/backups"
exec 9>"$state/maintenance.lock"
flock -n 9 || {
	echo 'Zulip maintenance already running' >&2
	exit 1
}
pending=$(mktemp -d "$state/backups/.pending-XXXXXXXX")
paused=0
cleanup() {
	status=$?
	if [ "$paused" = 1 ]; then
		"$compose" unpause zulip || {
			echo 'Zulip unpause failed; operator recovery required' >&2
			status=1
		}
	fi
	rm -rf -- "$pending"
	exit "$status"
}
trap cleanup EXIT
# Set before calling pause: a timeout can mean the daemon performed the action.
paused=1
"$compose" pause zulip
"$compose" exec -T database pg_dump -U zulip --no-owner --no-acl zulip >"$pending/database.sql"
[ -s "$pending/database.sql" ]
printf '%s\n' 'Restore data/ into an empty matching Zulip volume and database.sql into an empty Zulip PostgreSQL database. Never overwrite a running stack.' >"$pending/restore.txt"
tar -czf "$pending/archive.tar.gz" -C "$state" data -C "$pending" database.sql restore.txt
"$compose" unpause zulip
paused=0
mv -- "$pending/archive.tar.gz" "$state/backups/zulip.tar.gz"
