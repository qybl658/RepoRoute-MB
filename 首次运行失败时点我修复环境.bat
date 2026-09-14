@echo off
chcp 65001 >nul
title RepoWayfinder-MB Environment Repair
echo RepoWayfinder-MB environment check and repair
echo.
echo Missing prerequisites are installed only after the CLI explains the impact and you explicitly answer y.
echo Existing broken tools are preserved for official repair. Licenses, UAC, WSL, virtualization, and restart choices remain yours.
echo.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\bootstrap.ps1" doctor --repair
set "CODE=%ERRORLEVEL%"
echo.
if "%CODE%"=="0" (
  echo Environment check finished.
) else (
  echo Environment repair is waiting or failed. Exit code: %CODE%
)
if not defined REPOWAYFINDER_NO_PAUSE pause
exit /b %CODE%
