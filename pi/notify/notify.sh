#!/bin/bash
# Send a Telegram message. Usage: notify.sh "text"   (or: echo text | notify.sh)
# Keep alerts short: bold first line, <= 15 lines. Exits 1 and logs Telegram's
# own error text when sending fails, so a broken alert never fails silently.
. "$(dirname "$0")/../lib.sh"
text=${1:-$(cat)}
[ -n "$TELEGRAM_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ] || { echo "TELEGRAM_TOKEN / TELEGRAM_CHAT_ID not set" >&2; exit 1; }
args=(--data-urlencode "chat_id=$TELEGRAM_CHAT_ID" --data-urlencode "text=$text" -d parse_mode=HTML -d disable_web_page_preview=true)
[ -n "$TELEGRAM_THREAD_ID" ] && args+=(-d "message_thread_id=$TELEGRAM_THREAD_ID")
# URL via --config on stdin: the bot token never shows up in `ps` for other users.
resp=$(printf 'url = "https://api.telegram.org/bot%s/sendMessage"
' "$TELEGRAM_TOKEN" | curl -sS -m 15 -K - "${args[@]}" 2>&1)
if [ "$(printf '%s' "$resp" | jq -r .ok 2>/dev/null)" != true ]; then
  echo "$(date '+%F %T') telegram failed: $(printf '%s' "$resp" | jq -r '.description // .' 2>/dev/null | head -c 300)" >&2
  exit 1
fi
