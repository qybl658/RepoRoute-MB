@echo off
chcp 65001 >nul
title RepoWayfinder-MB
echo RepoWayfinder-MB launcher
echo.
echo A packaged executable runs directly. A source checkout uses an existing MoonBit toolchain only for this process.
echo This launcher does not persist PATH, install software, accept licenses, elevate, or restart Windows.
echo.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\bootstrap.ps1" %*
set "CODE=%ERRORLEVEL%"
if not "%CODE%"=="0" (
  echo.
  echo RepoWayfinder-MB did not finish. Exit code: %CODE%
  echo If this was the first run, double-click: 首次运行失败时点我修复环境.bat
  if not defined REPOWAYFINDER_NO_PAUSE pause
)
exit /b %CODE%
