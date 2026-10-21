param(
    [ValidateRange(1024, 65535)][int]$Port = 7359,
    [ValidateSet('edge', 'chrome')][string]$Browser = 'edge',
    [switch]$CheckOnly
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $root
$flutter = Get-Command flutter -ErrorAction SilentlyContinue
$bundledFlutter = Join-Path $root '.toolchain/flutter/bin/flutter.bat'
if ($flutter) {
    $flutterPath = $flutter.Source
} elseif (Test-Path -LiteralPath $bundledFlutter) {
    $flutterPath = $bundledFlutter
} else {
    throw 'Install Flutter and add its bin directory to PATH first. See docs/SHARING.md.'
}
Write-Host 'Server-local client: existing backend services will not be changed.'
foreach ($apiPort in @(18080, 18082)) {
    try {
        $health = Invoke-RestMethod -Uri ("http://127.0.0.1:$apiPort/api/v1/health") -TimeoutSec 5
        if ($health.inference_connected) {
            Write-Host ("API $apiPort is reachable; inference is connected.")
        } else {
            Write-Warning ("API $apiPort is reachable, but inference is not ready.")
        }
    } catch {
        Write-Warning ("API $apiPort is not reachable. Check existing services and Windows/WSL loopback forwarding. No services were restarted.")
    }
}
foreach ($mediaPort in @(18443, 18445)) {
    $tcp = [Net.Sockets.TcpClient]::new()
    try {
        $pending = $tcp.ConnectAsync('127.0.0.1', $mediaPort)
        if (-not $pending.Wait(2000) -or -not $tcp.Connected) { throw 'Not reachable.' }
        Write-Host ("TURN TCP $mediaPort is reachable; a real call is still required for media verification.")
    } catch {
        Write-Warning ("TURN TCP $mediaPort is not reachable. Calls may not connect.")
    } finally {
        $tcp.Dispose()
    }
}
if ($CheckOnly) { return }
if (Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue) {
    throw ("Port $Port is occupied. Choose a different -Port. No existing process was stopped.")
}
& $flutterPath --no-version-check pub get
if ($LASTEXITCODE -ne 0) { throw 'Flutter dependency installation failed.' }
& $flutterPath --no-version-check run -d $Browser --web-hostname=127.0.0.1 --web-port=$Port
if ($LASTEXITCODE -ne 0) { throw 'The client preview stopped with an error.' }
