<#
.SYNOPSIS
    Live demo: two isolated Chromes started from two separate powershell.exe processes, then stopped and verified.
#>
Set-StrictMode -Version Latest
$mod = Join-Path (Split-Path -Parent $PSScriptRoot) 'FleetTestHarness.psm1'
Import-Module $mod -Force
$jobs = 1..2 | ForEach-Object {
    $out = Join-Path $env:TEMP ("demo$_-" + [guid]::NewGuid().ToString('N') + '.json')
    $cmd = "Import-Module '$mod'; Start-IsolatedChrome -Agent demo$_ -Headless | ConvertTo-Json -Compress"
    [pscustomobject]@{ Out = $out; Proc = (Start-Process powershell.exe -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-Command',$cmd -RedirectStandardOutput $out -PassThru -WindowStyle Hidden) }
}
$jobs | ForEach-Object { $_.Proc.WaitForExit(60000) | Out-Null }
$inst = @($jobs | ForEach-Object { Get-Content $_.Out -Raw | ConvertFrom-Json })
'--- started ---'
$inst | ForEach-Object {
    $v = Invoke-RestMethod "http://127.0.0.1:$($_.Port)/json/version" -TimeoutSec 5
    [pscustomobject]@{ Agent = $_.Agent; Pid = $_.Pid; Port = $_.Port; Profile = $_.ProfilePath; Browser = $v.Browser }
} | Format-Table -AutoSize | Out-String -Width 250
'--- stopped ---'
$inst | ForEach-Object {
    $r = Stop-IsolatedChrome $_
    $left = @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" | Where-Object { $_.CommandLine -like "*$($r.ProfilePath)*" }).Count
    [pscustomobject]@{ Profile = $r.ProfilePath; KilledPids = ($r.Killed -join ','); ProfileDeleted = $r.ProfileDeleted; ProfileExists = (Test-Path $r.ProfilePath); StrayChrome = $left }
} | Format-Table -AutoSize | Out-String -Width 250
$jobs | ForEach-Object { Remove-Item $_.Out -ErrorAction SilentlyContinue }
