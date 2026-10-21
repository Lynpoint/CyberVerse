$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'
$env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn'
$env:ANDROID_HOME = Join-Path $projectRoot '.toolchain/android-sdk'
$env:GRADLE_USER_HOME = Join-Path $projectRoot '.toolchain/gradle-cache'
$javaFolder = Get-ChildItem (Join-Path $projectRoot '.toolchain') -Directory -Filter '*jdk17*win_x64' | Select-Object -First 1
if ($javaFolder) { $env:JAVA_HOME = $javaFolder.FullName }
$env:PATH = "$(Join-Path $projectRoot '.toolchain/flutter/bin');$env:JAVA_HOME\bin;$env:ANDROID_HOME\platform-tools;$env:PATH"
Set-Location $projectRoot
$systemProxy = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue
if ($systemProxy.ProxyEnable -eq 1 -and $systemProxy.ProxyServer -match '^([^:;]+):([0-9]+)$') {
  $proxyHost = $Matches[1]
  $proxyPort = $Matches[2]
  $env:JAVA_TOOL_OPTIONS = "-Dhttp.proxyHost=$proxyHost -Dhttp.proxyPort=$proxyPort -Dhttps.proxyHost=$proxyHost -Dhttps.proxyPort=$proxyPort"
}
