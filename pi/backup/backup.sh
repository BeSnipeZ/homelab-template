#!/bin/bash
# Daily: consistent SQLite copies (backup API, safe while the service runs), one file per
# weekday = 7 days rolling. The PC pulls BACKUP_DIR with pc/backup-pull.ps1 so a dead SD card
# or SSD does not take the only copy with it.
. "$(dirname "$0")/../lib.sh"
umask 077  # copies hold the same data as the live databases
day=$(date +%u)
fail=""
mkdir -p "$BACKUP_DIR"
backup() { # backup NAME SOURCE_DB
  [ -r "$2" ] || { fail="$fail $1(missing)"; return; }
  mkdir -p "$BACKUP_DIR/$1"
  sqlite3 "$2" ".backup '$BACKUP_DIR/$1/$1-$day.db'" 2>/dev/null || fail="$fail $1"
}
backup dashboard "$HL_ROOT/pi/dashboard/data.db"
# Uptime Kuma's database belongs to root inside the container dir; copy it only when readable.
[ -r /srv/uptime-kuma/kuma.db ] && backup kuma /srv/uptime-kuma/kuma.db
if [ -z "$fail" ]; then kuma_push "$KUMA_PUSH_BACKUP" up "ok day $day"
else kuma_push "$KUMA_PUSH_BACKUP" down "failed:$fail"; "$HL_ROOT/pi/notify/notify.sh" "<b>Backup failed</b>
$fail" 2>/dev/null; exit 1; fi
