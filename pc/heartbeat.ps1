# Every 15 min (scheduled task "Homelab Heartbeat"): tell the Pi this PC is alive.
# Dashboard shows host, uptime and free disk; Kuma alerts when the heartbeat stops or disk < 10 %.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'env.ps1')
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$drive = Get-PSDrive -Name $Cfg.PC_WATCH_DRIVE
$freePct = [math]::Round(100 * $drive.Free / ($drive.Used + $drive.Free))
$uptimeH = [math]::Round(((Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime).TotalHours, 1)
$body = @{ host = $env:COMPUTERNAME; diskFreePct = $freePct; uptimeH = $uptimeH } | ConvertTo-Json -Compress

try {
    $base = if ($Cfg.DASHBOARD_URL) { $Cfg.DASHBOARD_URL } else { "https://$($Cfg.TS_HOST)" }
    Invoke-RestMethod -Method Post -Uri "$base/api/pc" -ContentType 'application/json' -Body $body `
        -Headers @{ Authorization = "Bearer $($Cfg.DASHBOARD_TOKEN)" } -TimeoutSec 15 | Out-Null
} catch { Write-HlLog "dashboard heartbeat failed: $($_.Exception.Message)" }

$status = if ($freePct -lt 10) { 'down' } else { 'up' }
Send-KumaPush $Cfg.KUMA_PUSH_PC $status "$($Cfg.PC_WATCH_DRIVE): $freePct% free, up $uptimeH h"
