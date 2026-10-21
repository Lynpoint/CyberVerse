$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path $PSScriptRoot 'connect-backend.ps1'
$cases = @(
  @{ Params = @{}; Expected = @('127.0.0.1:8080:127.0.0.1:8080', ' cyberverse') },
  @{ Params = @{ Profile = 'BackendDev'; IncludeUpstreamUi = $true; IncludeMedia = $true }; Expected = @('127.0.0.1:8081:127.0.0.1:8081', '127.0.0.1:5174:127.0.0.1:5174', '127.0.0.1:8444:127.0.0.1:8444') },
  @{ Params = @{ Profile = 'FrontendAssist'; SshHost = '192.0.2.10'; SshUser = 'developer'; SshPort = 2222 }; Expected = @('127.0.0.1:8082:127.0.0.1:8082', '-l developer', '-p 2222', ' 192.0.2.10') },
  @{ Params = @{ ApiLocalPort = 18080; RemoteAddress = '172.20.1.2' }; Expected = @('127.0.0.1:18080:172.20.1.2:8080') }
)
foreach ($case in $cases) {
  $parameters = $case.Params
  $result = & $scriptPath @parameters -DryRun
  foreach ($part in $case.Expected) {
    if (-not $result.Contains($part)) { throw ('Missing expected argument: ' + $part) }
  }
  if (-not $result.StartsWith('ssh -N -T ')) { throw 'Unexpected command output' }
}
$invalidCases = @(
  @{ ApiLocalPort = 5173; IncludeUpstreamUi = $true },
  @{ Profile = 'BackendDev'; ApiLocalPort = 8444; IncludeMedia = $true },
  @{ SshHost = 'host;bad-command' },
  @{ SshUser = '-bad' },
  @{ RemoteAddress = '127.0.0.1:8080' },
  @{ Profile = 'Missing' },
  @{ SshPort = 0 }
)
foreach ($parameters in $invalidCases) {
  $rejected = $false
  try { & $scriptPath @parameters -DryRun | Out-Null } catch { $rejected = $true }
  if (-not $rejected) { throw 'Invalid parameters were accepted' }
}
Write-Output 'PASS: 11 offline SSH argument and validation cases. No network connections made.'
