# homelab-template

A small, boring, self-hosted homelab for one Raspberry Pi and one Windows PC — the generic core of the setup I run at home, with everything personal removed.

- **Dashboard** (Node, zero dependencies, installable PWA): Pi health, systemd services, PC heartbeat, to-dos.
- **Uptime Kuma** with push monitors: alerts when a service dies *or when a check stops reporting*.
- **Tailscale** as the only way in: HTTPS inside your tailnet, nothing exposed to the internet or your LAN.
- **Backups**: rolling 7-day SQLite copies on the Pi, pulled to the PC every day.
- **Telegram alerts** (optional) from scripts and from Kuma.
- **Firewall** pattern that locks chosen ports to loopback + Tailscale without touching Docker's rules.

## Architecture

```
            your phone / laptop (Tailscale app)
                          │  HTTPS, tailnet only
                          ▼
┌──────────────────── Raspberry Pi ────────────────────┐
│ tailscale serve :443  ──► dashboard  127.0.0.1:3000  │
│ tailscale serve :8443 ──► Uptime Kuma 127.0.0.1:3001 │
│                                                      │
│ cron  */5  services-push.sh ──► Kuma push            │
│       hourly disk-health.sh (SMART, fill, power)     │
│       04:20 backup.sh ──► ~/backups (7 days)         │
│ nft table "homelab": LOCKED_PORTS only lo+tailscale0 │
└───────────────▲──────────────────────▲───────────────┘
                │ POST /api/pc (token)  │ scp (ssh key)
┌───────────────┴──── Windows PC ───────┴──────────────┐
│ task "Homelab Heartbeat"   every 15 min              │
│ task "Homelab Backup Pull" daily ──► PC_BACKUP_DIR   │
└──────────────────────────────────────────────────────┘
        Kuma / scripts ──► Telegram (optional)
```

## Quick start

**Pi** (Raspberry Pi OS / Debian 12+, 64-bit):

```bash
git clone https://github.com/BeSnipeZ/homelab-template.git
cd homelab-template
./setup.sh        # first run creates .env with defaults and stops
nano .env         # check values, add Telegram if you want alerts
./setup.sh        # installs Node 22, Docker, Tailscale, services, firewall, cron
```

Then open `https://<pi>.<tailnet>.ts.net:8443`, create the Uptime Kuma admin account and run:

```bash
sudo python3 pi/kuma/add-monitors.py
```

**Windows PC** (PowerShell 5.1 or 7, no admin needed):

```powershell
git clone https://github.com/BeSnipeZ/homelab-template.git
cd homelab-template
powershell -ExecutionPolicy Bypass -File .\setup.ps1   # creates .env, stops
# copy TS_HOST, DASHBOARD_TOKEN, KUMA_PUSH_*, BACKUP_DIR from the Pi's .env, set PI_SSH + PC_BACKUP_DIR
powershell -ExecutionPolicy Bypass -File .\setup.ps1   # registers the two scheduled tasks
```

The PC needs key-based ssh to the Pi for the backup pull (`ssh-keygen -t ed25519`, then append the public key to the Pi's `~/.ssh/authorized_keys`).

## What is where

| Path | Purpose |
|---|---|
| `.env.example` | every setting in one place; copy to `.env` (git-ignored, `chmod 600`) |
| `setup.sh` / `setup.ps1` | idempotent installers for Pi / PC |
| `pi/dashboard/` | dashboard server, PWA and tests (`node test.js`) |
| `pi/health/` | `services-push.sh`, `disk-health.sh` → Kuma |
| `pi/backup/backup.sh` | SQLite backup API copies, one file per weekday |
| `pi/notify/notify.sh` | `notify.sh "<b>Disk almost full</b>"` → Telegram (HTML), logs the API error on failure |
| `pi/kuma/add-monitors.py` | creates all monitors in Kuma, skips existing ones |
| `pi/firewall/`, `pi/systemd/`, `pi/cron/` | templates rendered by `setup.sh` |
| `pc/` | heartbeat, backup pull, hidden launcher for scheduled tasks |
| `pi/optional/pi5-fan-curve.sh` | quieter fan curve for the Pi 5 Active Cooler |

## Optional

- **Telegram**: leave `TELEGRAM_*` empty and nothing is sent. Kuma has its own Telegram notification (Settings → Notifications) for monitor alerts.
- **Pi 5 fan curve**: `sudo bash pi/optional/pi5-fan-curve.sh`.
- **Without Tailscale serve**: set `DASHBOARD_URL` on the PC; keep `DASHBOARD_HOST=127.0.0.1` unless you put your own auth in front.
- **More services to watch**: add unit names to `WATCH_SERVICES`.

Not included on purpose: anything hardware-specific (RGB keyboards, smart lights, voice assistant) and anything finance-related. They lived in my private setup and do not generalise.

## Security model

- The dashboard has **no login of its own**. It binds to `127.0.0.1`; `tailscale serve` publishes it to your tailnet only, so Tailscale is the authentication. Do not bind it to `0.0.0.0` on a shared network.
- Browser writes must be same-origin (CSRF guard); the PC heartbeat uses a bearer token compared in constant time. Bodies are capped at 64 KB, inputs validated, strict CSP and `nosniff` headers set.
- The systemd unit runs as your user with `ProtectSystem=strict`, `NoNewPrivileges` and write access only to the dashboard folder.
- `.env` is `chmod 600` on the Pi and restricted to your user on Windows. Kuma's data folder is `chmod 700` (its database holds notification tokens).
- The `homelab` nftables table drops `LOCKED_PORTS` on every interface except `lo` and `tailscale0` — defence in depth if something binds to all interfaces. Undo: `sudo systemctl disable --now homelab-fw && sudo nft delete table inet homelab`.
- `setup.sh` installs Node, Docker and Tailscale from their official install scripts (`deb.nodesource.com`, `get.docker.com`, `tailscale.com/install.sh`). Read them first if you prefer.

## Tests

```bash
cd pi/dashboard && node test.js
```

Covers validation, to-do lifecycle, path traversal, CSRF guard, token check, body limit and unit-name filtering.

## License

MIT — see [LICENSE](LICENSE).
