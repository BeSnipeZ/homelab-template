# Sourced by every Pi script: loads .env from the repo root (or $HL_ENV).
# shellcheck shell=bash
HL_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
HL_ENV=${HL_ENV:-$HL_ROOT/.env}
if [ ! -r "$HL_ENV" ]; then echo "missing $HL_ENV (copy .env.example to .env)" >&2; exit 1; fi
set -a
# shellcheck disable=SC1090
. "$HL_ENV"
set +a
KUMA_URL="http://127.0.0.1:${KUMA_PORT:-3001}/api/push"

# kuma_push TOKEN up|down MESSAGE — silent no-op when the token is empty.
kuma_push() {
  [ -n "$1" ] || return 0
  curl -fsS -m 10 -G "$KUMA_URL/$1" --data-urlencode "status=$2" --data-urlencode "msg=$3" >/dev/null \
    || echo "$(date '+%F %T') kuma push failed ($2: $3)" >&2
}
