param(
  [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_.-]*$')]
  [string]$SshHost = 'cyberverse',
  [string]$PublicKeyPath = (Join-Path $env:USERPROFILE '.ssh/id_ed25519.pub'),
  [switch]$CopyForRemoteSession,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
if ($DryRun -and $CopyForRemoteSession) {
  throw 'Choose either DryRun or CopyForRemoteSession.'
}
$ssh = Join-Path $env:WINDIR 'System32/OpenSSH/ssh.exe'
$keygen = Join-Path $env:WINDIR 'System32/OpenSSH/ssh-keygen.exe'
if ([IO.Path]::GetExtension($PublicKeyPath) -ne '.pub') {
  throw 'Only an existing .pub public-key file is accepted. Never supply a private key.'
}
$publicKey = [IO.File]::ReadAllText($PublicKeyPath).Trim()
if ($publicKey -notmatch '^ssh-ed25519 ([A-Za-z0-9+/]+={0,2})(?:[ \t]+[^\r\n]*)?$') {
  throw 'Expected a single existing Ed25519 public-key line.'
}
$key = 'ssh-ed25519 ' + $Matches[1]
$fingerprint = & $keygen -lf $PublicKeyPath
if ($LASTEXITCODE -ne 0) { throw 'Public key validation failed.' }

# This helper targets the Windows administrator configuration verified for adm.
# https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_keymanagement
$remoteScript = @'
$ErrorActionPreference = 'Stop'
Write-Output 'REMOTE_SETUP_STARTED: authenticated; validating the server before any changes.'
if ($env:USERNAME -ine 'adm') { throw 'Expected the Windows adm account; nothing changed.' }
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  throw 'An enabled administrator token is required; nothing changed.'
}
$key = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__PUBLIC_KEY_BASE64__'))
$dir = Join-Path $env:ProgramData 'ssh'
$file = Join-Path $dir 'administrators_authorized_keys'
$service = Get-CimInstance Win32_Service -Filter "Name='sshd'"
if (-not $service -or $service.PathName -match '(?i)\s-f(?:\s|\")') {
  throw 'Missing sshd or a custom config path: inspect the server before making changes.'
}
$sshd = Join-Path $env:WINDIR 'System32/OpenSSH/sshd.exe'
$connection = ([string]$env:SSH_CONNECTION).Trim() -split '\s+'
$criteria = 'user=adm'
if ($connection.Count -eq 4) {
  $criteria = 'user=adm,host={0},addr={0},laddr={1},lport={2}' -f $connection[0],$connection[2],$connection[3]
} else {
  # VS Code and elevated terminals may not inherit SSH_CONNECTION.
  # A user-only test is sufficient for the verified Match Group administrators
  # configuration, but must not silently skip network rules or included files.
  $configLines = Get-Content -LiteralPath (Join-Path $dir 'sshd_config') -ErrorAction Stop
  $requiresConnection = @($configLines | Where-Object {
    $_ -match '^\s*Include\s' -or
    ($_ -match '^\s*Match\s' -and
      $_ -notmatch '^\s*Match\s+(?:All|(?:User|Group)\s+\S+)\s*(?:#.*)?$')
  })
  if ($requiresConnection.Count -gt 0) {
    throw 'This sshd config needs additional connection context or included-file review; no key files changed.'
  }
  Write-Output 'ACCOUNT_CONFIG_CHECK: SSH_CONNECTION unavailable; checking the adm account and group rules.'
}
Write-Output 'CHECKING_SSHD_CONFIG: read-only configuration validation.'
$effective = & $sshd -T -C $criteria
if ($LASTEXITCODE -ne 0) { throw 'Cannot validate effective sshd configuration; nothing changed.' }
$entry = @($effective | Where-Object { $_ -match '^authorizedkeysfile ' })
if ($entry.Count -ne 1) { throw 'Unexpected authorized-key configuration; nothing changed.' }
$path = $entry[0].Substring('authorizedkeysfile '.Length).Trim().Trim('"')
$path = $path.Replace('__PROGRAMDATA__', $env:ProgramData).Replace('/', '\')
if ($path -ine $file -or $effective -notcontains 'pubkeyauthentication yes') {
  throw 'Effective sshd settings differ from the verified admin-key setup; nothing changed.'
}
Write-Output 'SSHD_CONFIG_VALIDATED: preparing the key-file backup.'
$utf8 = New-Object Text.UTF8Encoding($false, $true)
$content = ''
$backup = $null
if (Test-Path -LiteralPath $file) {
  $bytes = [IO.File]::ReadAllBytes($file)
  if ($bytes.Length -ge 2 -and (($bytes[0] -eq 255 -and $bytes[1] -eq 254) -or ($bytes[0] -eq 254 -and $bytes[1] -eq 255))) {
    throw 'Existing key file is UTF-16; preserve it and review encoding before retrying.'
  }
  $content = $utf8.GetString($bytes)
  $originalAcl = Get-Acl -LiteralPath $file
  $backup = $file + '.before-shiyi-key-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,6)
  Copy-Item -LiteralPath $file -Destination $backup
  $sddl = $originalAcl.GetSecurityDescriptorSddlForm([Security.AccessControl.AccessControlSections]::All)
  [IO.File]::WriteAllText($backup + '.acl.sddl', $sddl, $utf8)
  Write-Output ('BACKUP_READY: ' + $backup)
} else {
  [IO.File]::WriteAllText($file, '', $utf8)
}

# Protect this file only; do not change the ssh directory or service config.
$acl = New-Object Security.AccessControl.FileSecurity
$acl.SetAccessRuleProtection($true, $false)
$adminSid = New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')
$systemSid = New-Object Security.Principal.SecurityIdentifier('S-1-5-18')
$acl.SetOwner($adminSid)
foreach ($sid in @($adminSid, $systemSid)) {
  $rule = New-Object Security.AccessControl.FileSystemAccessRule($sid, 'FullControl', 'Allow')
  $acl.AddAccessRule($rule)
}
Set-Acl -LiteralPath $file -AclObject $acl

# Existing entries, including keys with restrictions, are never replaced.
$pattern = '(^|\s)' + [regex]::Escape($key) + '(\s|$)'
$exists = @($content -split '\r?\n' | Where-Object { $_ -notmatch '^\s*#' -and $_ -match $pattern }).Count -gt 0
if (-not $exists) {
  $prefix = ''
  if ($content.Length -gt 0 -and -not $content.EndsWith([string][char]10)) { $prefix = [Environment]::NewLine }
  [IO.File]::AppendAllText($file, $prefix + $key + [Environment]::NewLine, $utf8)
}
Write-Output ('AUTHORIZED_KEY_READY: ' + $file)
if ($backup) { Write-Output ('BACKUP: ' + $backup) }
Write-Output 'Existing keys retained. No service restart or password-authentication change.'
'@
$keyBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($key))
$remoteScript = $remoteScript.Replace('__PUBLIC_KEY_BASE64__', $keyBase64)

if ($CopyForRemoteSession) {
  # Run the existing setup logic inside the already-authenticated remote shell.
  # The block stops on errors even when pasted into an interactive console.
  $pasteBlock = '& {' + [Environment]::NewLine + $remoteScript + [Environment]::NewLine + '}'
  Set-Clipboard -Value $pasteBlock
  Write-Output ('Public key: ' + $fingerprint)
  Write-Output 'COPIED_FOR_REMOTE_SESSION: paste into your existing SERVER adm PowerShell session and press Enter.'
  Write-Output 'Only the public key is included. No SSH connection or server changes were made by this copy step.'
  Write-Output 'After AUTHORIZED_KEY_READY, use a new local terminal to verify key-only login.'
  return
}

# A short encoded loader avoids the Windows SSH command-length limit.
$loader = @'
try {
  # The sender writes one base64 line; do not wait for the SSH stdin stream to close.
  $line = [Console]::In.ReadLine()
  if ([string]::IsNullOrWhiteSpace($line)) { throw 'No setup payload received; nothing changed.' }
  $text = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($line.Trim()))
  & ([ScriptBlock]::Create($text))
} catch {
  [Console]::Error.WriteLine($_.Exception.Message)
  exit 1
}
'@
$encodedLoader = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($loader))
$payload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($remoteScript))
$sshArgs = @('-T', '-o', 'StrictHostKeyChecking=yes', '-o', 'ConnectTimeout=15', '-o', 'ConnectionAttempts=1', '-o', 'ClearAllForwardings=yes')
Write-Output ('Target: ' + $SshHost + ' / Windows adm administrator key file')
Write-Output ('Public key: ' + $fingerprint)
if ($DryRun) {
  Write-Output 'DRY RUN: local public key validated; no SSH connection or server changes.'
  return
}

Write-Host 'Keep your existing server session open. Enter the SERVER password locally if prompted.'
Write-Host 'This appends your public key and restricts this shared admin key file to Administrators/SYSTEM.'
Write-Host 'Watch for REMOTE_SETUP_STARTED, SSHD_CONFIG_VALIDATED, and AUTHORIZED_KEY_READY.'
$payload | & $ssh @sshArgs $SshHost ('powershell.exe -NoLogo -NoProfile -NonInteractive -EncodedCommand ' + $encodedLoader)
if ($LASTEXITCODE -ne 0) {
  throw ('SSH/setup exited with code {0}. Completion is unknown after a timeout. Keep the existing session; share the SSH error and last stage marker. Do not rerun blindly or restart shared services.' -f $LASTEXITCODE)
}

Write-Host 'Checking a fresh key-only connection...'
& $ssh @sshArgs -o BatchMode=yes -o PreferredAuthentications=publickey $SshHost 'powershell.exe -NoLogo -NoProfile -NonInteractive -Command Write-Output KEY_LOGIN_OK'
if ($LASTEXITCODE -ne 0) {
  throw 'Key-only verification failed. An encrypted key may need your local ssh-agent; also check server logs. Do not delete keys or disable passwords.'
}
