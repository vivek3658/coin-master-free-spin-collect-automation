@echo off
title Coin Master Fastify Auto-Pilot Engine
echo ================================================================
echo Starting Coin Master Fastify High-Performance Server...
echo ================================================================

:: Automatically forward phone localhost:3000 to laptop port 3000 via ADB
where adb >nul 2>&1
if %ERRORLEVEL% equ 0 (
    echo [*] Bridging smartphone localhost:3000 to laptop via ADB reverse...
    adb reverse tcp:3000 tcp:3000
) else if exist "%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe" (
    echo [*] Bridging smartphone localhost:3000 to laptop via Android SDK ADB...
    "%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe" reverse tcp:3000 tcp:3000
)

cd /d "%~dp0"
node server.js
pause
