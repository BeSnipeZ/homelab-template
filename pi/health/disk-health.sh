#!/bin/bash
# Hourly as root (smartctl needs it): SMART health + fill level + Pi power state to Kuma.
# setup.sh installs a root-owned copy as /usr/local/sbin/homelab-disk-health, and this script
# only reads plain values from .env (no sourcing): root never runs code your user can edit.
# Usage: homelab-disk-health /path/to/.env
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin  # cron has no /usr/sbin -> smartctl "missing"
set -f  # no globbing of values read from .env
ENV_FILE=${1:?usage: $0 /path/to/.env}
get() { sed -n "s/^$1=//p" "$ENV_FILE" | tail -1 | sed -E "s/^([\"'])(.*)\1\$/\2/"; }
DISK=$(get DISK_DEVICE); DISK=${DISK:-/dev/sda}
SMART_ARGS=$(get SMART_ARGS)
PORT=$(get KUMA_PORT); PORT=${PORT:-3001}
TOKEN=$(get KUMA_PUSH_DISK)
[[ $DISK =~ ^/dev/[A-Za-z0-9/_-]+$ && $PORT =~ ^[0-9]+$ && $TOKEN =~ ^[A-Za-z0-9_-]*$ && $SMART_ARGS =~ ^[A-Za-z0-9\ ,=_-]*$ ]] \
  || { echo "$(date '+%F %T') unsafe value in $ENV_FILE (DISK_DEVICE, KUMA_PORT, KUMA_PUSH_DISK or SMART_ARGS)" >&2; exit 1; }

# shellcheck disable=SC2086  # SMART_ARGS is a word list on purpose
s=$(smartctl -H -A $SMART_ARGS "$DISK" 2>&1)
ok=$(echo "$s" | grep -cE 'test result: PASSED|SMART Health Status: OK')
realloc=$(echo "$s" | awk '$1==5 {print $10}')
temp=$(echo "$s" | awk '$1==194 {print $10}')
full=$(df --output=pcent / | tail -1 | tr -dc 0-9)
# Pi only: undervoltage silently drops USB SSDs. Bits 0-3 = right now (undervolt, freq cap, throttled, temp limit).
thr=0x0
command -v vcgencmd >/dev/null && thr=$(vcgencmd get_throttled | cut -d= -f2)
status=up
[ "$ok" -ge 1 ] && [ "${realloc:-0}" = 0 ] && [ "$full" -lt 90 ] && [ $((thr & 0xF)) = 0 ] || status=down
msg="smart $ok realloc ${realloc:-?} temp ${temp:-?}C full $full% power $thr"
[ -n "$TOKEN" ] || exit 0
curl -fsS -m 10 -G "http://127.0.0.1:$PORT/api/push/$TOKEN" --data-urlencode "status=$status" --data-urlencode "msg=$msg" >/dev/null \
  || echo "$(date '+%F %T') kuma push failed ($status: $msg)" >&2
