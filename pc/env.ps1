# Dot-sourced by the PC scripts: reads ..\.env into $Cfg (hashtable). Windows PowerShell 5.1+.
$HlRoot = Split-Path -Parent $PSScriptRoot
$EnvFile = Join-Path $HlRoot '.env'
if (-not (Test-Path $EnvFile)) { throw "missing $EnvFile (copy .env.example to .env)" }
$Cfg = @{}
foreach ($line in [IO.File]::ReadAllLines($EnvFile, [Text.Encoding]::UTF8)) {
    if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)=(.*)$') {
        $v = $Matches[2].Trim()
        if ($v.Length -ge 2 -and ($v[0] -eq '"' -or $v[0] -eq "'") -and $v[-1] -eq $v[0]) { $v = $v.Substring(1, $v.Length - 2) }
        $Cfg[$Matches[1]] = $v
    }
}
$Log = Join-Path $PSScriptRoot 'homelab-pc.log'
function Write-HlLog($text) { Add-Content -Path $Log -Encoding UTF8 -Value ('{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $text) }

# Push to an Uptime Kuma push monitor through Tailscale serve (port 8443).
function Send-KumaPush($token, $status, $msg) {
    if (-not $token -or -not $Cfg.TS_HOST) { return }
    $url = 'https://{0}:8443/api/push/{1}?status={2}&msg={3}' -f $Cfg.TS_HOST, $token, $status, [Uri]::EscapeDataString($msg)
    try { Invoke-RestMethod -Uri $url -TimeoutSec 15 | Out-Null } catch { Write-HlLog "kuma push failed: $($_.Exception.Message)" }
}
