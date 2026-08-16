@echo off
rem Toggle auto-start for both balance widgets (silent launch)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0toggle-autostart.ps1"
echo.
pause
