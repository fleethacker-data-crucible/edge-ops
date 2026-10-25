# ToolName host. Windows PowerShell 5.1 only. ASCII only (PS 5.1 reads BOM-less .ps1 as ANSI).
# Started by ToolName.lnk (conhost.exe --headless, no console window). See edge-ops CONVENTIONS.md.
#   powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File src\Start-ToolName.ps1 [-Port n] [-NoBrowser] [-CheckOnly]
param([int]$Port = 0, [switch]$NoBrowser, [switch]$CheckOnly)
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = Split-Path -Parent $here

# Logs: <root>\logs\ToolName_yyyy_MM_dd_HHmmss.log, one file per run.
$logFile = Join-Path $root ('logs\ToolName_{0:yyyy_MM_dd_HHmmss}.log' -f (Get-Date))
New-Item -ItemType Directory -Force (Split-Path $logFile) | Out-Null
function Add-Log([string]$level, [string]$text) {
    try { [IO.File]::AppendAllText($logFile, "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  [$level] $text`r`n") } catch { }
}
# The console is hidden, so a fatal error goes to the log and a message box.
function Show-Fatal([string]$text) {
    Add-Log 'FATAL' $text
    try {
        Add-Type -AssemblyName System.Windows.Forms
        [void][System.Windows.Forms.MessageBox]::Show("ToolName could not start.`n`n$text`n`nLog: $logFile", 'ToolName')
    } catch { }
}
trap { Show-Fatal "$($_.Exception.Message) (line $($_.InvocationInfo.ScriptLineNumber))"; exit 1 }

if ($PSVersionTable.PSVersion.Major -ne 5) { throw "Run with Windows PowerShell 5.1 (powershell.exe), not $($PSVersionTable.PSVersion)." }

# Temp files (Add-Type scratch, .NET temp) stay inside the tool folder.
$env:TEMP = Join-Path $root 'temp\sys'; $env:TMP = $env:TEMP
New-Item -ItemType Directory -Force $env:TEMP | Out-Null

# Settings: <here>\settings.json holds the remembered port and options.
$settingsFile = Join-Path $here 'settings.json'
$settings = if (Test-Path $settingsFile) { Get-Content $settingsFile -Raw | ConvertFrom-Json } else { [pscustomobject]@{ port = 8771 } }
if ($Port -gt 0) { $settings.port = $Port }

if ($CheckOnly) { Add-Log 'sys' 'Self-check passed.'; Write-Host 'Self-check passed.'; exit 0 }

# Stop OUR previous instance only (pid file + command line check). Never another program.
$pidFile = Join-Path $here '.pid'
if (Test-Path $pidFile) {
    $old = Get-CimInstance Win32_Process -Filter "ProcessId=$([int](Get-Content $pidFile))" -ErrorAction SilentlyContinue
    if ($old -and $old.CommandLine -like '*Start-ToolName.ps1*') { Stop-Process -Id $old.ProcessId -Force; Start-Sleep -Milliseconds 500 }
}
Set-Content $pidFile $PID

. (Join-Path $here 'LoopbackPort.ps1')
$listener = Start-LoopbackListener -PreferredPort $settings.port -RangeStart 8771 -RangeEnd 8779
$actual = Get-ListenerPort -Listener $listener
if ($actual -ne $settings.port) { Add-Log 'sys' "Port $($settings.port) is busy; using $actual." }
$url = "http://127.0.0.1:$actual/"
Add-Log 'sys' "Serving $url (PID $PID, PowerShell $($PSVersionTable.PSVersion))"
if (-not $NoBrowser) { Start-Process $url }
try {
    while ($listener.IsListening) {
        $ctx = $listener.GetContext()
        if (-not (Test-LocalRequest -Request $ctx.Request -Port $actual)) { $ctx.Response.StatusCode = 403; $ctx.Response.Close(); continue }
        $bytes = [Text.Encoding]::UTF8.GetBytes('ok')
        $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
        $ctx.Response.Close()
    }
} finally {
    $listener.Close()
    Remove-Item $pidFile -ErrorAction SilentlyContinue
}
