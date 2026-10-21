@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "scriptsopen-shiyi-voice-app.ps1"
if errorlevel 1 pause
