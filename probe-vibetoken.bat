@echo off
rem VibeToken interface probe (run when the widget cannot connect)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0probe-vibetoken.ps1"
echo.
pause
