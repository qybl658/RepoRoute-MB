@echo off
chcp 65001 >nul
title RepoWayfinder-MB 环境修复
echo RepoWayfinder-MB 环境检查与修复
echo.
echo 仅当 CLI 说明影响且你明确输入 y 后，才会安装缺失的前置工具。
echo 已损坏的现有工具会保留，供官方方式修复；许可、UAC、WSL、虚拟化和重启仍由你决定。
echo.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\bootstrap.ps1" doctor --repair
set "CODE=%ERRORLEVEL%"
echo.
if "%CODE%"=="0" (
  echo 环境检查已完成。
) else (
  echo 环境修复正在等待用户操作或已失败，退出代码：%CODE%
)
if not defined REPOWAYFINDER_NO_PAUSE pause
exit /b %CODE%
