@echo off
setlocal EnableExtensions DisableDelayedExpansion

rem Transparent local installer. Requires Windows 10/11 x64 and an elevated CMD window.
rem No PowerShell, remote download, execution-policy change, or Defender exclusion is used.

set "ROOT=%~dp0.."
set "EXE=%ROOT%\app\GuardianPaws.exe"
if not exist "%EXE%" (
  echo GuardianPaws.exe is missing from the release package.
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

if "%~1"=="" (
  echo Usage:
  echo   Install-GuardianPaws.cmd ^<child-user-name^> ^<display-name^> ^<extension-update-url^>
  echo Example:
  echo   Install-GuardianPaws.cmd GuardianChild "Child account" "https://guard.catbiologymc.com/guardian-paws/update.xml"
  exit /b 2
)

"%EXE%" install --child "%~1" --display "%~2" --extension-update-url "%~3"
exit /b %errorlevel%
