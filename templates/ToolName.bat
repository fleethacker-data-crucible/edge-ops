@echo off
setlocal
rem ToolName launcher. -ExecutionPolicy Bypass applies ONLY to this process; it does not
rem change machine policy, need admin, or override Group Policy / AppLocker / WDAC.
set "POWERSHELL=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%POWERSHELL%" (
  echo [ToolName] Windows PowerShell 5.1 was not found.
  pause
  exit /b 1
)
"%POWERSHELL%" -NoLogo -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0Start-ToolName.ps1" %*
set "RESULT=%ERRORLEVEL%"
if not "%RESULT%"=="0" (
  echo.
  echo [ToolName] Startup failed ^(exit code %RESULT%^). See the error above.
  pause
)
exit /b %RESULT%
