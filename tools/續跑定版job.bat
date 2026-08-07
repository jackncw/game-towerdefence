@echo off
chcp 65001 >nul
rem 20-seed 定版 job:雙擊就由斷點續跑。
rem 隨時可以閂窗;下次再雙擊會由停低嗰個單位接落去,已經跑完嘅唔會重跑。
rem 跑完之後睇報告:雙擊 tools\定版job出報告.bat
cd /d "%~dp0.."
echo ============================================================
echo   20-seed 定版 job(可以隨時閂窗,下次雙擊由斷點續跑)
echo   輸出:qa\bench\gate\r21\
echo ============================================================
powershell -NoProfile -ExecutionPolicy Bypass -File "tools\gate20.ps1"
echo.
echo ============================================================
echo   收工。仲未跑完就再雙擊呢個檔一次。
echo   全部跑完之後,雙擊 tools\定版job出報告.bat 睇 Gate 表。
echo ============================================================
pause
