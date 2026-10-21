. "$PSScriptRoot/env.ps1"
flutter --no-version-check analyze
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
flutter --no-version-check test
exit $LASTEXITCODE
