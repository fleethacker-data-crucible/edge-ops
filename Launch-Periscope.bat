@echo off
rem Periscope local host. Windows PowerShell 5.1, loopback only, no admin.
rem The .bat stays at the edge-ops repo root. The host script stays under tools\periscope\.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0tools\periscope\Periscope.ps1" %*
pause
