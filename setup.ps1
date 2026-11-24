# Windows PC setup (Windows PowerShell 5.1 or PowerShell 7). Run from the repo folder:
#   powershell -ExecutionPolicy Bypass -File .\setup.ps1
# Registers two scheduled tasks for the current user (no admin needed):
#   Homelab Heartbeat    every 15 min  pc\heartbeat.ps1
#   Homelab Backup Pull  daily 12:30   pc\backup-pull.ps1
# Remove them again with:  .\setup.ps1 -Uninstall
param([switch]$Uninstall)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$tasks = @{ 'Homelab Heartbeat' = 'heartbeat.ps1'; 'Homelab Backup Pull' = 'backup-pull.ps1' }

if ($Uninstall) {
    foreach ($name in $tasks.Keys) { Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue }
    Write-Host 'Scheduled tasks removed.'
    exit 0
}

if (-not (Test-Path "$root\.env")) {
    Copy-Item "$root\.env.example" "$root\.env"
    Write-Host 'Created .env. Copy the values from the Pi''s .env (TS_HOST, DASHBOARD_TOKEN, KUMA_PUSH_*, BACKUP_DIR),'
    Write-Host 'set PI_SSH and PC_BACKUP_DIR, then run setup.ps1 again.'
    exit 0
}
. "$root\pc\env.ps1"
foreach ($k in 'TS_HOST', 'DASHBOARD_TOKEN', 'PI_SSH', 'PC_BACKUP_DIR', 'PC_WATCH_DRIVE') {
    if (-not $Cfg[$k]) { throw "$k is empty in .env" }
}
if ($Cfg.TS_HOST -like '*example*') { throw 'TS_HOST still has the example value' }

# Only the current user may read .env (it holds the tokens).
icacls "$root\.env" /inheritance:r /grant:r "$($env:USERNAME):(R,W)" | Out-Null

$ErrorActionPreference = 'Continue' # PS 5.1: native stderr + 'Stop' = terminating error
ssh -o BatchMode=yes -o ConnectTimeout=8 $Cfg.PI_SSH true 2>$null
$sshOk = $LASTEXITCODE -eq 0
$ErrorActionPreference = 'Stop'
if (-not $sshOk) {
    Write-Warning "ssh $($Cfg.PI_SSH) without password failed. Create a key (ssh-keygen -t ed25519) and add it to the Pi's ~/.ssh/authorized_keys, or backups cannot be pulled."
}

$wscript = Join-Path $env:WINDIR 'System32\wscript.exe'
$vbs = Join-Path $root 'pc\run-hidden.vbs'
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 30)
$every15 = New-ScheduledTaskTrigger -Once -At (Get-Date).Date -RepetitionInterval (New-TimeSpan -Minutes 15) -RepetitionDuration (New-TimeSpan -Days 3650)
$triggers = @{ 'Homelab Heartbeat' = @($every15, (New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME)); 'Homelab Backup Pull' = @(New-ScheduledTaskTrigger -Daily -At '12:30') }
foreach ($name in $tasks.Keys) {
    $action = New-ScheduledTaskAction -Execute $wscript -Argument ('"{0}" "{1}"' -f $vbs, (Join-Path $root "pc\$($tasks[$name])"))
    Register-ScheduledTask -TaskName $name -Action $action -Trigger $triggers[$name] -Settings $settings -Force | Out-Null
    Write-Host "registered: $name"
}

Write-Host 'Running the heartbeat once...'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'pc\heartbeat.ps1')
Write-Host "Done. The PC should appear on https://$($Cfg.TS_HOST) within a minute. Log: pc\homelab-pc.log"
