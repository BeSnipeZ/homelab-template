"""Create the homelab monitors in Uptime Kuma (v2, SQLite) once the admin account exists.

Run as root after you opened Kuma and created the admin user:
    sudo python3 pi/kuma/add-monitors.py
Existing monitor names are skipped, so it is safe to run again after adding entries.
Dry run against a copy: KUMA_DB=/tmp/kuma-copy.db python3 pi/kuma/add-monitors.py
"""

import os
import pathlib
import sqlite3
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
ENV_FILE = pathlib.Path(os.environ.get("HL_ENV", ROOT / ".env"))
DB = os.environ.get("KUMA_DB", "/srv/uptime-kuma/kuma.db")


def load_env(path):
    env = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            key, value = line.split("=", 1)
            env[key.strip()] = value.strip().strip('"').strip("'")
    return env


ENV = load_env(ENV_FILE)
H = 3600
PORT = ENV.get("DASHBOARD_PORT", "3000")
MONITORS = [  # name, type, extra columns
    ("Dashboard (local)", "http", {"url": f"http://127.0.0.1:{PORT}/api/health", "interval": 60}),
    ("Dashboard via Tailscale", "http", {"url": f"https://{ENV.get('TS_HOST', 'localhost')}/api/health", "interval": 300,
                                         "accepted_statuscodes_json": '["200-399"]'}),
    ("Pi services (systemd)", "push", {"push_token": ENV.get("KUMA_PUSH_SERVICES"), "interval": 600}),
    ("Pi disk (SMART)", "push", {"push_token": ENV.get("KUMA_PUSH_DISK"), "interval": 2 * H}),
    ("Pi backup", "push", {"push_token": ENV.get("KUMA_PUSH_BACKUP"), "interval": 26 * H}),
    ("PC heartbeat", "push", {"push_token": ENV.get("KUMA_PUSH_PC"), "interval": 3 * H}),
    ("PC pulled backups", "push", {"push_token": ENV.get("KUMA_PUSH_PC_BACKUP"), "interval": 26 * H}),
]


def main():
    if not pathlib.Path(DB).exists():
        sys.exit(f"{DB} not found - is the uptime-kuma container running?")
    con = sqlite3.connect(DB)
    uid = con.execute("select min(id) from user").fetchone()[0]
    if uid is None:
        sys.exit("No Kuma account yet: open Kuma, create the admin user, then run this again.")
    existing = {r[0] for r in con.execute("select name from monitor")}
    added = []
    for name, kind, extra in MONITORS:
        if name in existing:
            continue
        if kind == "push" and not extra.get("push_token"):
            print(f"skip {name}: push token empty in .env (run setup.sh first)")
            continue
        cols = {"name": name, "type": kind, "user_id": uid, "timeout": 48, "maxretries": 1, "retry_interval": 60, **extra}
        con.execute(f"insert into monitor ({','.join(cols)}) values ({','.join('?' * len(cols))})", list(cols.values()))
        added.append(name)
    con.commit()
    con.close()
    print("added:", ", ".join(added) or "nothing new")
    if added and not os.environ.get("KUMA_DB"):
        subprocess.run(["docker", "restart", "uptime-kuma"], check=True)  # Kuma reads monitors only at start


if __name__ == "__main__":
    main()
