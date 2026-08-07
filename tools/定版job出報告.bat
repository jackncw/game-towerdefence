@echo off
chcp 65001 >nul
rem 20-seed 定版 job 嘅 Gate 報告。未跑完都出得,但數字係部分樣本,唔可以當定版。
cd /d "%~dp0.."
powershell -NoProfile -ExecutionPolicy Bypass -File "tools\gate20.ps1" -Status
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "tools\gate20.ps1" -Report
echo.
pause
