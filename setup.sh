#!/bin/bash
# Raspberry Pi setup (Raspberry Pi OS / Debian 12+, arm64). Run as your normal user from the
# repo folder:   ./setup.sh
# Safe to run again: every step checks what is already there. Uses sudo where root is needed.
set -euo pipefail
cd "$(dirname "$0")"
ROOT=$(pwd)

say() { printf '\n\033[1;35m==>\033[0m %s\n' "$*"; }
[ "$(id -u)" -ne 0 ] || { echo "Run as your normal user, not root (sudo is used where needed)." >&2; exit 1; }

# --- 1. .env ------------------------------------------------------------------
if [ ! -f .env ]; then
  cp .env.example .env
  sed -i "s|^HL_DIR=.*|HL_DIR=$ROOT|; s|^HL_USER=.*|HL_USER=$(id -un)|; s|^BACKUP_DIR=.*|BACKUP_DIR=$HOME/backups|" .env
  chmod 600 .env
  echo "Created .env with defaults for this machine. Review it (Telegram, TS_HOST), then run ./setup.sh again."
  exit 0
fi
chmod 600 .env
# Fill empty secrets with random tokens.
for key in DASHBOARD_TOKEN KUMA_PUSH_SERVICES KUMA_PUSH_DISK KUMA_PUSH_BACKUP KUMA_PUSH_PC KUMA_PUSH_PC_BACKUP; do
  if grep -qE "^$key=$" .env; then sed -i "s|^$key=$|$key=$(head -c 18 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 24)|" .env; fi
done
set -a; . ./.env; set +a
[ "$HL_DIR" = "$ROOT" ] || { echo "HL_DIR in .env ($HL_DIR) is not this folder ($ROOT)." >&2; exit 1; }
render() { envsubst "$(printf '${%s} ' HL_DIR HL_USER LOCKED_PORTS)" < "$1"; }

# --- 2. packages ----------------------------------------------------------------
say "Packages"
sudo apt-get update -qq
sudo apt-get install -y -qq curl jq sqlite3 smartmontools nftables gettext-base ca-certificates python3 >/dev/null
node_ok() { command -v node >/dev/null && node -e 'const [a,b]=process.versions.node.split(".").map(Number);process.exit(a>22||(a===22&&b>=13)?0:1)'; }
if ! node_ok; then
  say "Node.js 22 (NodeSource)"
  curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - >/dev/null
  sudo apt-get install -y -qq nodejs >/dev/null
fi
if ! command -v docker >/dev/null; then
  say "Docker (get.docker.com)"
  curl -fsSL https://get.docker.com | sudo sh >/dev/null
fi
if ! command -v tailscale >/dev/null; then
  say "Tailscale"
  curl -fsSL https://tailscale.com/install.sh | sh
fi
if ! tailscale status >/dev/null 2>&1; then
  say "Tailscale login: open the URL below and approve this device"
  sudo tailscale up
fi

# --- 3. dashboard ---------------------------------------------------------------
say "Dashboard service"
render pi/systemd/dashboard.service.tmpl | sudo tee /etc/systemd/system/dashboard.service >/dev/null
sudo systemctl daemon-reload
sudo systemctl enable --now dashboard
sudo systemctl restart dashboard

# --- 4. Uptime Kuma -------------------------------------------------------------
say "Uptime Kuma (Docker, localhost only)"
if ! sudo docker inspect uptime-kuma >/dev/null 2>&1; then
  sudo mkdir -p /srv/uptime-kuma && sudo chmod 700 /srv/uptime-kuma  # kuma.db holds notification tokens
  sudo docker run -d --name uptime-kuma --restart unless-stopped \
    -p "127.0.0.1:${KUMA_PORT}:3001" -v /srv/uptime-kuma:/app/data louislam/uptime-kuma:2 >/dev/null
fi

# --- 5. Tailscale serve: HTTPS inside the tailnet only ----------------------------
say "tailscale serve"
sudo tailscale serve --bg --https=443 "http://127.0.0.1:${DASHBOARD_PORT}" >/dev/null
sudo tailscale serve --bg --https=8443 "http://127.0.0.1:${KUMA_PORT}" >/dev/null

# --- 6. firewall -------------------------------------------------------------------
say "Firewall: ports ${LOCKED_PORTS} only via lo + tailscale0"
render pi/firewall/homelab-fw.nft.tmpl | sudo tee /etc/homelab-fw.nft >/dev/null
sudo cp pi/systemd/homelab-fw.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable homelab-fw >/dev/null 2>&1
sudo systemctl restart homelab-fw

# --- 7. cron -------------------------------------------------------------------------
say "Cron jobs (/etc/cron.d/homelab)"
chmod +x pi/*/*.sh
# root's hourly job: a root-owned copy, so editing the repo as your user never runs code as root
sudo install -o root -g root -m 755 pi/health/disk-health.sh /usr/local/sbin/homelab-disk-health
render pi/cron/homelab.cron.tmpl | sudo tee /etc/cron.d/homelab >/dev/null
sudo chmod 644 /etc/cron.d/homelab

# --- 8. check ----------------------------------------------------------------------
say "Check"
sleep 2
curl -fsS "http://127.0.0.1:${DASHBOARD_PORT}/api/health" && echo "  dashboard ok"
systemctl is-active -q homelab-fw && echo "  firewall ok"
TS_NAME=$(tailscale status --json | jq -r '.Self.DNSName' | sed 's/\.$//')
cat <<EOF

Done. Next steps:
  1. Set TS_HOST=$TS_NAME in .env (PC scripts use it).
  2. Open https://$TS_NAME:8443 and create the Uptime Kuma admin account,
     then run:  sudo python3 pi/kuma/add-monitors.py
  3. Dashboard: https://$TS_NAME  (add it to your phone's home screen).
  4. Optional Telegram alerts: fill TELEGRAM_* in .env, test with pi/notify/notify.sh "<b>Hello</b>",
     and add Telegram as notification in Kuma (Settings -> Notifications).
EOF
