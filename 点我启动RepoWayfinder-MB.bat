@echo off
chcp 65001 >nul
title RepoWayfinder-MB 启动器
echo RepoWayfinder-MB 启动器
echo.
echo 已打包的可执行文件会直接运行；源码目录仅在当前进程中使用现有 MoonBit 工具链。
echo 本启动器不会永久修改 PATH、安装软件、接受许可、提权或重启 Windows。
echo.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\bootstrap.ps1" %*
set "CODE=%ERRORLEVEL%"
if not "%CODE%"=="0" (
  echo.
  echo RepoWayfinder-MB 未能完成，退出代码：%CODE%
  echo 如果这是首次运行，请双击：首次运行失败时点我修复环境.bat
  if not defined REPOWAYFINDER_NO_PAUSE pause
)
exit /b %CODE%
