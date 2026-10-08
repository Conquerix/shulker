#!/usr/bin/env bash
# Failures must preserve data and attempt recovery only for previously active writers.
set -euo pipefail
script=$1
trial=$(mktemp -d)
trap 'rm -rf "$trial"' EXIT
mkdir -p "$trial/bin" "$trial/state" "$trial/backups"
echo keep >"$trial/state/data"
export OH_TEST_LOG="$trial/calls" OH_TEST_STOP_FAIL=0 OH_TEST_START_FAIL=0 OH_TEST_ACTIVE=1
cat >"$trial/bin/systemctl" <<'MOCK'
#!/usr/bin/env bash
echo "$1" >> "$OH_TEST_LOG"
case "$1" in
is-active) [ "$OH_TEST_ACTIVE" = 1 ] ;;
stop) [ "$OH_TEST_STOP_FAIL" = 0 ] ;;
start) [ "$OH_TEST_START_FAIL" = 0 ] ;;
esac
MOCK
chmod +x "$trial/bin/systemctl"
export PATH="$trial/bin:$PATH"
bash "$script" fixture.service "$trial/backups/worker.tar.gz" "$trial/state"
tar -tzf "$trial/backups/worker.tar.gz" | grep -q state/data
[ "$(stat -c %a "$trial/backups/worker.tar.gz")" = 600 ]
export OH_TEST_STOP_FAIL=1
if bash "$script" fixture.service "$trial/backups/worker.tar.gz" "$trial/state"; then exit 1; fi
[ "$(tail -1 "$OH_TEST_LOG")" = start ]
export OH_TEST_STOP_FAIL=0 OH_TEST_START_FAIL=1
if bash "$script" fixture.service "$trial/backups/worker.tar.gz" "$trial/state"; then exit 1; fi
[ "$(cat "$trial/state/data")" = keep ]

# A failed copy must restart the writer and leave the previous archive intact.
export OH_TEST_START_FAIL=0
cp "$trial/backups/worker.tar.gz" "$trial/prior.tar.gz"
cat >"$trial/bin/tar" <<'MOCK'
#!/usr/bin/env bash
exit 1
MOCK
chmod +x "$trial/bin/tar"
if bash "$script" fixture.service "$trial/backups/worker.tar.gz" "$trial/state"; then exit 1; fi
[ "$(tail -1 "$OH_TEST_LOG")" = start ]
cmp "$trial/prior.tar.gz" "$trial/backups/worker.tar.gz"
rm "$trial/bin/tar"
# Inactive writers stay inactive; symlinks remain links and SQLite is restorable.
export OH_TEST_ACTIVE=0
: >"$OH_TEST_LOG"
echo outside-private >"$trial/outside"
ln -s ../outside "$trial/state/link"
python - "$trial/state/journal.sqlite" <<'PYTEST'
import sqlite3,sys
with sqlite3.connect(sys.argv[1]) as db:
 db.execute('create table task(id text)');db.execute("insert into task values ('fixture')")
PYTEST
bash "$script" fixture.service "$trial/backups/worker.tar.gz" "$trial/state"
[ "$(cat "$OH_TEST_LOG")" = is-active ]
mkdir "$trial/restore"
tar -xzf "$trial/backups/worker.tar.gz" -C "$trial/restore"
[ -L "$trial/restore/state/link" ]
[ ! -f "$trial/restore/outside" ]
python - "$trial/restore/state/journal.sqlite" <<'PYTEST'
import sqlite3,sys
with sqlite3.connect(sys.argv[1]) as db:
 assert db.execute('pragma integrity_check').fetchone()==('ok',)
 assert db.execute('select id from task').fetchall()==[('fixture',)]
PYTEST
