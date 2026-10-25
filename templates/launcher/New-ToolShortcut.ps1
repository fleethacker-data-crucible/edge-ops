# Creates ToolName.lnk in the tool root, the FleetHacker launcher (pattern from phoenix-lai and data-noodler).
# The shortcut runs conhost.exe --headless so no console window appears (no VBS needed), and finds its
# own folder at run time, so the extracted folder can live anywhere. No admin rights.
#   powershell.exe -NoProfile -File templates\launcher\New-ToolShortcut.ps1 -Root C:\Tools\ToolName -Name ToolName -Script src\Start-ToolName.ps1
param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$Script,   # relative to $Root, e.g. src\Start-ToolName.ps1
    [string]$Icon = '%SystemRoot%\System32\shell32.dll,13',   # use a path relative to %SystemRoot%, never a dev-machine path
    [string]$Description = $Name
)
$ErrorActionPreference = 'Stop'
# Same bootstrap phoenix-lai's .lnk files use: read the .lnk path from STARTUPINFO, then run the script beside it.
$boot = "Add-Type 'public class S{[System.Runtime.InteropServices.DllImport(""kernel32"")]public static extern void GetStartupInfoW(byte[] b);}';" +
        "`$b=New-Object byte[] 104;[S]::GetStartupInfoW(`$b);" +
        "`$t=[Runtime.InteropServices.Marshal]::PtrToStringUni([IntPtr][BitConverter]::ToInt64(`$b,24));" +
        "& (Join-Path (Split-Path `$t) '$Script')"
$enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($boot))
$sh = New-Object -ComObject WScript.Shell
$lnk = $sh.CreateShortcut((Join-Path $Root "$Name.lnk"))
$lnk.TargetPath = '%SystemRoot%\System32\conhost.exe'
$lnk.Arguments = "--headless %SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -EncodedCommand $enc"
$lnk.IconLocation = $Icon
$lnk.Description = $Description
$lnk.Save()
Write-Host "Created $Name.lnk -> $Script"
