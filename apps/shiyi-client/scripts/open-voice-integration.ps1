param([switch]$NoBrowser)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$runtime = Join-Path $root '.toolchain/runtime/voice-integration'
[void](New-Item -ItemType Directory -Path $runtime -Force)
$url = 'http://127.0.0.1:15173/shiyi-voice.html'
function Get-VoiceHealth {
    try { return Invoke-RestMethod 'http://127.0.0.1:18080/api/v1/health' -TimeoutSec 8 } catch { return $null }
}
$health = Get-VoiceHealth
if (-not $health) {
    Write-Output 'Starting or reusing the isolated WSL voice services...'
    & ssh.exe -T -o BatchMode=yes -o ConnectTimeout=30 -o StrictHostKeyChecking=yes -o ClearAllForwardings=yes `
        cyberverse 'wsl.exe -d Ubuntu -- bash /home/user/cyberverse-workspaces/integration/.shiyi-integration/start.sh'
    if ($LASTEXITCODE -ne 0) { throw 'Unable to start the integration services. Existing shared services were not changed.' }
    $occupied = Get-NetTCPConnection -State Listen -LocalPort 18080,15173,18443 -ErrorAction SilentlyContinue
    $process = $null
    $metadataPath = Join-Path $runtime 'tunnel.json'
    if (Test-Path -LiteralPath $metadataPath) {
        try {
            $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
            $candidate = Get-Process -Id ([int]$metadata.pid) -ErrorAction SilentlyContinue
            if ($candidate -and $candidate.ProcessName -eq 'ssh') { $process = $candidate }
        } catch { $process = $null }
    }
    if ($occupied -and -not $process) { throw 'A preview port is already occupied. No existing process was stopped.' }
    $arguments = @('-N','-T','-o','BatchMode=yes','-o','ConnectTimeout=30','-o','ExitOnForwardFailure=yes',
        '-o','ServerAliveInterval=30','-o','ServerAliveCountMax=5',
        '-L','127.0.0.1:18080:127.0.0.1:18080',
        '-L','127.0.0.1:15173:127.0.0.1:15173',
        '-L','127.0.0.1:18443:127.0.0.1:18443','cyberverse')
    if (-not $process) {
        $process = Start-Process -FilePath 'ssh.exe' -ArgumentList $arguments -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput (Join-Path $runtime 'ssh.out.log') -RedirectStandardError (Join-Path $runtime 'ssh.err.log')
        @{pid=$process.Id;started=(Get-Date).ToString('o');host='cyberverse'} | ConvertTo-Json |
        Set-Content -LiteralPath (Join-Path $runtime 'tunnel.json') -Encoding UTF8
    }
    for ($i=0; $i -lt 90; $i++) {
        Start-Sleep -Seconds 1
        $process.Refresh()
        if ($process.HasExited) { throw ('SSH tunnel stopped. See '+(Join-Path $runtime 'ssh.err.log')) }
        $health = Get-VoiceHealth
        if ($health -and $health.inference_connected) { break }
    }
}
if (-not $health -or -not $health.inference_connected) { throw 'The integration inference service is not connected.' }
$pageReady = $false
for ($i=0; $i -lt 30; $i++) {
    try {
        $response = Invoke-WebRequest -UseBasicParsing $url -TimeoutSec 10
        if ($response.StatusCode -eq 200 -and $response.Content -match 'shiyi-voice\.js') {
            $pageReady = $true
            break
        }
    } catch { }
    Start-Sleep -Seconds 2
}
if (-not $pageReady) { throw 'The voice page is not ready. Check integration/.shiyi-integration/logs/web.log on the server.' }
Write-Output ('VOICE_PREVIEW_READY '+$url)
if (-not $NoBrowser) { Start-Process $url }
