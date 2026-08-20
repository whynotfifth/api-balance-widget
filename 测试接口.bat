@echo off
rem VibeToken 403 diagnostic - send output to the author
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0test-api.ps1"
echo.
pause
