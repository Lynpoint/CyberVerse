param(
  [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_.-]*$')]
  [string]$SshHost = 'cyberverse',
  [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_.-]*$')]
  [string]$SshUser,
  [ValidateRange(1, 65535)]
  [Nullable[int]]$SshPort,
  [ValidateSet('Integration', 'BackendDev', 'FrontendAssist')]
  [string]$Profile = 'Integration',
  [ValidateRange(1024, 65535)]
  [Nullable[int]]$ApiLocalPort,
  [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_.-]*$')]
  [string]$RemoteAddress = '127.0.0.1',
  [switch]$IncludeUpstreamUi,
  [switch]$IncludeMedia,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
if (-not $DryRun -and -not (Get-Command ssh -ErrorAction SilentlyContinue)) {
  throw 'Install Windows OpenSSH Client first.'
}
$profiles = @{
  Integration = @{ Api = 8080; Ui = 5173; Turn = 8443 }
  BackendDev = @{ Api = 8081; Ui = 5174; Turn = 8444 }
  FrontendAssist = @{ Api = 8082; Ui = 5175; Turn = 8445 }
}
$ports = $profiles[$Profile]
if ($null -eq $ApiLocalPort) { $ApiLocalPort = $ports.Api }
$localPorts = @($ApiLocalPort)
if ($IncludeUpstreamUi) { $localPorts += $ports.Ui }
if ($IncludeMedia) { $localPorts += $ports.Turn }
if (@($localPorts | Select-Object -Unique).Count -ne $localPorts.Count) {
  throw 'Local forwarding ports must be different.'
}
$sshArgs = @(
  '-N', '-T', '-o', 'ExitOnForwardFailure=yes',
  '-o', 'ServerAliveInterval=30', '-o', 'ServerAliveCountMax=3',
  '-L', ('127.0.0.1:{0}:{1}:{2}' -f $ApiLocalPort, $RemoteAddress, $ports.Api)
)
if ($IncludeUpstreamUi) {
  $sshArgs += @('-L', ('127.0.0.1:{0}:{1}:{0}' -f $ports.Ui, $RemoteAddress))
}
if ($IncludeMedia) {
  $sshArgs += @('-L', ('127.0.0.1:{0}:{1}:{0}' -f $ports.Turn, $RemoteAddress))
}
if ($SshUser) { $sshArgs += @('-l', $SshUser) }
if ($null -ne $SshPort) { $sshArgs += @('-p', $SshPort.ToString()) }
$sshArgs += $SshHost
if ($DryRun) {
  Write-Output ('ssh ' + ($sshArgs -join ' '))
  return
}
Write-Host ('Environment: {0}. Server ports must already match this profile.' -f $Profile)
Write-Host ('API tunnel: http://127.0.0.1:{0}' -f $ApiLocalPort)
Write-Host 'Keep this terminal open. Press Ctrl+C to stop forwarding.'
if ($IncludeMedia) {
  Write-Host ('TURN TCP port: {0}. Server-advertised ICE settings must match; this does not configure media networking.' -f $ports.Turn)
}
& ssh @sshArgs
exit $LASTEXITCODE
