param([switch]$NoBrowser)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/env.ps1"
$root = Split-Path $PSScriptRoot -Parent
$runtime = Join-Path $root '.toolchain/runtime/avatar-integration'
New-Item -ItemType Directory -Force $runtime | Out-Null
$remoteRoot = '/home/user/cyberverse-workspaces/frontend-assist'
$remoteCommand = 'wsl.exe -d Ubuntu -- docker compose --env-file ' + $remoteRoot + '/.shiyi-avatar/compose.env -f ' + $remoteRoot + '/scripts/avatar-assist/compose.yaml up -d'
& ssh.exe -T -o BatchMode=yes -o ConnectTimeout=20 cyberverse $remoteCommand
if ($LASTEXITCODE -ne 0) { throw 'Avatar services could not start. Shared services were not stopped.' }
$startProxy = 'wsl.exe -d Ubuntu -- python3 ' + $remoteRoot + '/scripts/avatar-assist/start_proxy.py'
& ssh.exe -T -o BatchMode=yes -o ConnectTimeout=20 cyberverse $startProxy
if ($LASTEXITCODE -ne 0) { throw 'Avatar loopback bridge could not start.' }
$health = $null
try { $health = Invoke-RestMethod 'http://127.0.0.1:18082/api/v1/health' -TimeoutSec 4 } catch {}
if (-not $health) {
    foreach ($port in @(18082,18445)) {
        if (Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort $port -State Listen -ErrorAction SilentlyContinue) {
            throw "Local port $port is occupied. No existing process was stopped."
        }
    }
    $arguments = @('-N','-T','-o','BatchMode=yes','-o','ConnectTimeout=20','-o','ExitOnForwardFailure=yes',
        '-o','ServerAliveInterval=20','-o','ServerAliveCountMax=3',
        '-L','127.0.0.1:18082:127.0.0.1:18082','-L','127.0.0.1:18445:127.0.0.1:18445','cyberverse')
    $tunnel = Start-Process ssh.exe -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $runtime 'ssh.out.log') -RedirectStandardError (Join-Path $runtime 'ssh.err.log')
    $tunnel.Id | Set-Content (Join-Path $runtime 'ssh.pid')
}
for ($i=0; $i -lt 25; $i++) {
    try { $health = Invoke-RestMethod 'http://127.0.0.1:18082/api/v1/health' -TimeoutSec 4 } catch { $health = $null }
    if ($health -and $health.inference_connected) { break }
    Start-Sleep -Seconds 2
}
if (-not $health -or -not $health.inference_connected) { throw 'Avatar inference is not ready. Check the isolated avatar service logs.' }
Write-Host 'SHIYI_AVATAR_READY http://127.0.0.1:18082'
& "$PSScriptRoot/open-shiyi-voice-app.ps1" -NoBrowser:$NoBrowser
