param([switch]$NoBrowser)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/env.ps1"
& "$PSScriptRoot/open-voice-integration.ps1" -NoBrowser
$output = Join-Path (Split-Path $PSScriptRoot -Parent) 'build/web/main.dart.js'
$sources = @(Get-ChildItem lib,web,assets -File -Recurse) + @(Get-Item pubspec.yaml,pubspec.lock)
$needsBuild = -not (Test-Path -LiteralPath $output)
if (-not $needsBuild) {
    $builtAt = (Get-Item -LiteralPath $output).LastWriteTimeUtc
    $needsBuild = @($sources | Where-Object { $_.LastWriteTimeUtc -gt $builtAt }).Count -gt 0
}
if ($needsBuild) {
    flutter --no-version-check build web --release --no-web-resources-cdn --no-wasm-dry-run
    if ($LASTEXITCODE -ne 0) { throw 'The App build failed. No existing service was changed.' }
}
try {
    $existing = Invoke-WebRequest -UseBasicParsing 'http://127.0.0.1:7358/' -TimeoutSec 3
} catch { $existing = $null }
if ($existing) {
    if ($existing.Content -notmatch 'flutter_bootstrap.js') {
        throw 'Port 7358 belongs to another service. No existing process was stopped.'
    }
    if (-not $NoBrowser) { Start-Process 'http://127.0.0.1:7358/' }
} else {
    $runtime = Join-Path (Split-Path $PSScriptRoot -Parent) '.toolchain/runtime/app-preview'
    New-Item -ItemType Directory -Force $runtime | Out-Null
    $python = (Get-Command python -ErrorAction Stop).Source
    $preview = Start-Process -FilePath $python -ArgumentList @(('"' + (Join-Path $PSScriptRoot 'serve-web-preview.py') + '"'), '--no-browser') -WorkingDirectory (Split-Path $PSScriptRoot -Parent) -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $runtime 'preview.out.log') -RedirectStandardError (Join-Path $runtime 'preview.err.log')
    $preview.Id | Set-Content (Join-Path $runtime 'preview.pid')
    $ready = $false
    for ($i=0; $i -lt 20; $i++) {
        try {
            $response = Invoke-WebRequest -UseBasicParsing 'http://127.0.0.1:7358/' -TimeoutSec 3
            if ($response.Content -match 'flutter_bootstrap.js') { $ready = $true; break }
        } catch {}
        Start-Sleep -Milliseconds 500
    }
    if (-not $ready) { throw 'App preview did not start. See .toolchain/runtime/app-preview/preview.err.log.' }
    if (-not $NoBrowser) { Start-Process 'http://127.0.0.1:7358/' }
}
