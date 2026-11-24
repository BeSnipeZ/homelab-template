#!/bin/bash
# Optional, Raspberry Pi 5 with the Active Cooler only: quieter fan curve.
# Stock: 50/60/67.5/75 °C, PWM 75/125/175/250, 5 °C hysteresis each.
# Here: the lowest step keeps running (10 °C hysteresis), step 2 only from 70 °C.
# Knobs: fan_tempN (milli-°C), fan_tempN_hyst, fan_tempN_speed (0-255).
# Usage: sudo bash pi/optional/pi5-fan-curve.sh  (thresholds apply now, config.txt from next boot)
set -e
CFG=/boot/firmware/config.txt
[ -w "$CFG" ] || { echo "run with sudo on a Pi 5" >&2; exit 1; }
cp "$CFG" "$CFG.bak-$(date +%Y%m%d-%H%M%S)"
sed -i '/^# homelab fan curve/,/^# end homelab fan curve/d' "$CFG"
cat >> "$CFG" <<'EOF'
# homelab fan curve
[all]
dtparam=fan_temp0=50000,fan_temp0_hyst=10000,fan_temp0_speed=75
dtparam=fan_temp1=70000,fan_temp1_hyst=6000,fan_temp1_speed=125
dtparam=fan_temp2=76000,fan_temp2_hyst=5000,fan_temp2_speed=175
dtparam=fan_temp3=80000,fan_temp3_hyst=5000,fan_temp3_speed=250
# end homelab fan curve
EOF
Z=/sys/class/thermal/thermal_zone0
# top-down so the order never inverts; hysteresis is read-only at runtime (applies after reboot)
echo 80000 > $Z/trip_point_4_temp
echo 76000 > $Z/trip_point_3_temp
echo 70000 > $Z/trip_point_2_temp
for t in 1 2 3 4; do echo "trip$t $(cat $Z/trip_point_${t}_temp) hyst $(cat $Z/trip_point_${t}_hyst)"; done
