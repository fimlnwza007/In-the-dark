@echo off
chcp 65001 >nul
title Alone in the Dusk - Server Launcher
color 0A

echo ===============================================
echo   ALONE IN THE DUSK - Auto Server Launcher
echo ===============================================
echo.

:: Check if Node.js is installed
where node >nul 2>nul
if errorlevel 1 (
    echo [ERROR] ไม่พบ Node.js กรุณาติดตั้งก่อน:
    echo         https://nodejs.org/
    pause
    exit /b 1
)

:: Check if node_modules exists, if not install dependencies
if not exist "%~dp0server\node_modules" (
    echo [INFO] กำลังติดตั้ง dependencies...
    cd /d "%~dp0server"
    call npm install
    cd /d "%~dp0"
)

echo [INFO] กำลังเริ่ม Signaling Server ที่ port 9080...
echo.

:: Start signaling server in background (new minimized window)
start "Alone in the Dusk - Signaling Server" /min cmd /k "cd /d ""%~dp0server"" && node signaling_server.js"

:: Wait a moment for server to start
timeout /t 2 /nobreak >nul

echo [OK] Server เริ่มแล้ว!
echo.

:: Check if the game web build exists and open it
if exist "%~dp0docs\index.html" (
    echo [INFO] กำลังเปิดเกมใน Browser...
    start "" "%~dp0docs\index.html"
) else if exist "%~dp0web\index.html" (
    echo [INFO] กำลังเปิดเกมใน Browser...
    start "" "%~dp0web\index.html"
) else (
    echo [INFO] ไม่พบ web build - เปิด Browser เองได้เลย
)

echo.
echo ===============================================
echo   Server ทำงานอยู่ใน window ที่ minimize ไว้
echo   ปิด window นั้นเพื่อหยุด Server
echo ===============================================
echo.
pause
