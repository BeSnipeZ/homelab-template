#!/bin/bash
# Every 5 min (cron): are all WATCH_SERVICES active? Result goes to the Kuma push monitor
# "Pi services"; Kuma alerts when a unit is down or when this script stops reporting.
. "$(dirname "$0")/../lib.sh"
down=""
for unit in $WATCH_SERVICES; do systemctl is-active -q "$unit" || down="$down $unit"; done
if [ -z "$down" ]; then kuma_push "$KUMA_PUSH_SERVICES" up "all active"
else kuma_push "$KUMA_PUSH_SERVICES" down "down:$down"; fi
