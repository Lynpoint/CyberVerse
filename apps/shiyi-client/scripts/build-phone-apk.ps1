. "$PSScriptRoot/env.ps1"
flutter --no-version-check build apk --release --target-platform android-arm64 --split-per-abi
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
New-Item -ItemType Directory -Force deliverables | Out-Null
Copy-Item build/app/outputs/flutter-apk/app-arm64-v8a-release.apk deliverables/Shiyi-demo-arm64.apk
Write-Host "Phone APK: $projectRoot\deliverables\Shiyi-demo-arm64.apk (demo signing)"
