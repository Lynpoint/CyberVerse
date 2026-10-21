@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\run-server-client.ps1" %*
set "result=%errorlevel%"
pause
exit /b %result%
