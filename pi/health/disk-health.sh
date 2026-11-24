#!/bin/bash
# Hourly as root (smartctl needs it): SMART health + fill level + Pi power state to Kuma.
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin  # cron has no /usr/sbin -> smartctl "missing"
. "$(dirname "$0")/../lib.sh"
# shellcheck disable=SC2086  # SMART_ARGS is a word list on purpose
s=$(smartctl -H -A $SMART_ARGS "${DISK_DEVICE:-/dev/sda}" 2>&1)
ok=$(echo "$s" | grep -cE 'test result: PASSED|SMART Health Status: OK')
realloc=$(echo "$s" | awk '$1==5 {print $10}')
temp=$(echo "$s" | awk '$1==194 {print $10}')
full=$(df --output=pcent / | tail -1 | tr -dc 0-9)
# Pi only: undervoltage silently drops USB SSDs. Bits 0-3 = right now (undervolt, freq cap, throttled, temp limit).
thr=0x0
command -v vcgencmd >/dev/null && thr=$(vcgencmd get_throttled | cut -d= -f2)
status=up
[ "$ok" -ge 1 ] && [ "${realloc:-0}" = 0 ] && [ "$full" -lt 90 ] && [ $((thr & 0xF)) = 0 ] || status=down
kuma_push "$KUMA_PUSH_DISK" "$status" "smart $ok realloc ${realloc:-?} temp ${temp:-?}C full $full% power $thr"
