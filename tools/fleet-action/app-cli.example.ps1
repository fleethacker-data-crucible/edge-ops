# Example CLI entry for a Fleet app (copy as <app>.ps1). ASCII only.
# Launch: powershell.exe -NoProfile -ExecutionPolicy Bypass -File capstan.ps1 marker add --clip clip_... --json
if ($PSVersionTable.PSVersion.Major -ne 5) { [Console]::Error.WriteLine('Run with Windows PowerShell 5.1 (powershell.exe).'); exit 1 }
Set-StrictMode -Version 2
Import-Module (Join-Path $PSScriptRoot 'FleetAction.psm1')
. (Join-Path $PSScriptRoot 'Capstan.Actions.ps1')   # Register-FleetAction calls
Invoke-FleetCli -App capstan -Argv $args
exit $LASTEXITCODE
