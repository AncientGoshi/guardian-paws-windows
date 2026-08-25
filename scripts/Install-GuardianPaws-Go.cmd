@echo off
setlocal EnableExtensions DisableDelayedExpansion
rem Transparent Go installer. Run from an elevated Command Prompt; no hidden task or shell is used.
set "ROOT=%~dp0.."
set "EXE=%ROOT%\app\GuardianPaws-Go.exe"
if not exist "%EXE%" (
  echo GuardianPaws-Go.exe is missing from the release package.
  exit /b 1
)
net session >nul 2>&1
if not "%errorlevel%"=="0" (
  echo Right-click Command Prompt and select Run as administrator, then run this file again.
  exit /b 1
)
if /I "%~1"=="uninstall" (
  "%EXE%" uninstall
  exit /b %errorlevel%
)
if "%~3"=="" (
  echo Usage: Install-GuardianPaws-Go.cmd ^<child-user-name^> ^<display-name^> ^<extension-update-url^>
  exit /b 2
)
"%EXE%" install --child "%~1" --display "%~2" --extension-update-url "%~3"
exit /b %errorlevel%
