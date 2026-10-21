@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\open-shiyi-avatar-app.ps1"
if errorlevel 1 pause
