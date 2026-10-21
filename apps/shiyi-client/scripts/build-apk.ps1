. "$PSScriptRoot/env.ps1"
flutter --no-version-check pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
flutter --no-version-check analyze
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
flutter --no-version-check test
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
flutter --no-version-check build apk --debug
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host "APK: $projectRoot\build\app\outputs\flutter-apk\app-debug.apk"
