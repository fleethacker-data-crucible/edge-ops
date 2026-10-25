@echo off
rem Developer / utility .bat (pattern from phoenix-lai Package.bat). Users start the tool from ToolName.lnk.
rem Visible console + pause so errors stay on screen. -ExecutionPolicy Bypass applies to this process only.
%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0src\Start-ToolName.ps1" %*
pause
