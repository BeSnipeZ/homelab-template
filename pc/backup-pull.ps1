# Daily (scheduled task "Homelab Backup Pull"): copy the Pi's rolling backups to this PC,
# so a dead Pi disk never takes the only copy. Needs key-based ssh to PI_SSH (no password prompt).
$ErrorActionPreference = 'Continue'  # 'Stop' turns ssh's stderr into a terminating error in PS 5.1
. (Join-Path $PSScriptRoot 'env.ps1')
$dest = $Cfg.PC_BACKUP_DIR
function Fail($why) { Write-HlLog "backup pull failed: $why"; Send-KumaPush $Cfg.KUMA_PUSH_PC_BACKUP 'down' $why; exit 1 }
try { New-Item -ItemType Directory -Force $dest -ErrorAction Stop | Out-Null } catch { Fail "PC_BACKUP_DIR unusable: $($_.Exception.Message)" }

# The Pi may be rebooting: knock up to three times before giving up.
for ($i = 0; $i -lt 3; $i++) {
    ssh -o BatchMode=yes -o ConnectTimeout=8 $Cfg.PI_SSH true 2>$null
    if ($LASTEXITCODE -eq 0) { break }
    Start-Sleep 20
}
$src = $Cfg.BACKUP_DIR
scp -r -q -o BatchMode=yes -o ConnectTimeout=8 "$($Cfg.PI_SSH):$src/*" "$dest\"
if ($LASTEXITCODE -ne 0) { Fail "scp exit $LASTEXITCODE" }
$n = @(Get-ChildItem $dest -Recurse -File -ErrorAction SilentlyContinue).Count
if ($n -eq 0) { Fail 'no files arrived' }
Write-HlLog "backup pull ok ($n files)"
Send-KumaPush $Cfg.KUMA_PUSH_PC_BACKUP 'up' "$n files"
