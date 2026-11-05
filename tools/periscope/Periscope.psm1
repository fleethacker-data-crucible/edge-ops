# Periscope host logic. Windows PowerShell 5.1. ASCII only.
# Utilities download only through a Gangplank child process. This module never imports Gangplank.
# No heartbeat and no update check: those stay a Day 30 plan and are not implemented here.
Set-StrictMode -Version 2

$script:GangplankReleaseUrl = ''
$script:GangplankReleaseSha256 = ''
$script:GangplankPorts = @(8769, 8770)

$script:DoGangplank = { param($Repo, $Dest, $Token, $ModulePath, $UseStore) @{ ok = $false; code = 'GANGPLANK_DISABLED'; message = 'Gangplank boundary is not enabled.' } }
$script:DoStart = { param($File, $WorkingDirectory) throw 'start boundary is not enabled' }
$script:DoDownload = { param($Url, $Sha, $Dest) @{ ok = $false; code = 'NO_RELEASE'; message = 'No pinned Gangplank release is recorded.' } }
$script:DoProbe = { $false }

function Enable-PeriscopeRuntime {
    $script:DoGangplank = { param($Repo, $Dest, $Token, $ModulePath, $UseStore) Invoke-PeriscopeGangplankChild -Repo $Repo -Dest $Dest -Token $Token -ModulePath $ModulePath -UseStore:$UseStore }
    $script:DoStart = { param($File, $WorkingDirectory) Start-Process -FilePath $File -WorkingDirectory $WorkingDirectory }
    $script:DoDownload = { param($Url, $Sha, $Dest) Invoke-PeriscopePinnedDownload -Url $Url -Sha256 $Sha -Dest $Dest }
    $script:DoProbe = { Test-PeriscopeGangplankListening }
}

function Set-PeriscopeBoundary {
    param($Gangplank, $Start, $Download, $Probe)
    if ($Gangplank) { $script:DoGangplank = $Gangplank }
    if ($Start) { $script:DoStart = $Start }
    if ($Download) { $script:DoDownload = $Download }
    if ($Probe) { $script:DoProbe = $Probe }
}

function Reset-PeriscopeBoundary {
    $script:DoGangplank = { param($Repo, $Dest, $Token, $ModulePath, $UseStore) @{ ok = $false; code = 'GANGPLANK_DISABLED'; message = 'Gangplank boundary is not enabled.' } }
    $script:DoStart = { param($File, $WorkingDirectory) throw 'start boundary is not enabled' }
    $script:DoDownload = { param($Url, $Sha, $Dest) @{ ok = $false; code = 'NO_RELEASE'; message = 'No pinned Gangplank release is recorded.' } }
    $script:DoProbe = { $false }
}

function New-PeriscopeEnvelope {
    param([string]$Action, $Result = $null, [string]$Code = 'OK', [string]$Message = '')
    $e = [ordered]@{ ok = ($Code -eq 'OK'); action = $Action; v = 1 }
    if ($Code -eq 'OK') { $e.result = $Result } else { $e.error = [ordered]@{ code = $Code; message = $Message } }
    $e.warnings = @()
    [pscustomobject]$e
}

function Get-PeriscopeLauncherName([string]$Launcher) {
    if (-not $Launcher) { return '' }
    $token = ($Launcher.Trim() -split '\s+', 2)[0]
    if ($token -match '[\\/]' -or $token -notmatch '^[A-Za-z0-9_.-]+\.bat$') { return '' }
    $token
}

function Test-PeriscopeToolId([string]$Id) { $Id -match '^[a-z0-9]+(-[a-z0-9]+)*$' }

function Test-PeriscopeLaunchable($Tool) {
    if (-not $Tool) { return $false }
    if (-not (Test-PeriscopeToolId ([string]$Tool.id))) { return $false }
    if ([string]$Tool.group -eq 'support') { return $false }
    return [bool](Get-PeriscopeLauncherName ([string]$Tool.launcher))
}

function Get-PeriscopeCatalogTool {
    param([Parameter(Mandatory)][string]$CatalogPath, [Parameter(Mandatory)][string]$Id)
    if (-not (Test-Path -LiteralPath $CatalogPath)) { return $null }
    $cat = Get-Content -LiteralPath $CatalogPath -Raw | ConvertFrom-Json
    foreach ($t in @($cat.tools)) { if ([string]$t.id -eq $Id) { return $t } }
    $null
}

function Get-PeriscopeUtilityDir {
    param([Parameter(Mandatory)][string]$AppData, [Parameter(Mandatory)][string]$Id)
    Join-Path (Join-Path $AppData 'Periscope') $Id
}

function Test-PeriscopeDownloadFolder {
    param([Parameter(Mandatory)][string]$Dir, [Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][string]$Id)
    if (-not (Test-Path -LiteralPath $Dir)) { return @{ ok = $true } }
    $markerPath = Join-Path $Dir '.periscope-download.json'
    $items = @(Get-ChildItem -LiteralPath $Dir -Force | Where-Object { $_.Name -ne '.periscope-download.json' })
    if (Test-Path -LiteralPath $markerPath) {
        try { $m = Get-Content -LiteralPath $markerPath -Raw | ConvertFrom-Json } catch { $m = $null }
        if ($m -and [string]$m.repo -eq $Repo -and [string]$m.id -eq $Id) { return @{ ok = $true } }
        return @{ ok = $false; message = 'Folder already exists, not a Periscope download' }
    }
    if ($items.Count -eq 0) { return @{ ok = $true } }
    @{ ok = $false; message = 'Folder already exists, not a Periscope download' }
}

function Write-PeriscopeMarker {
    param([Parameter(Mandatory)][string]$Dir, [Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][string]$Id)
    if (-not (Test-Path -LiteralPath $Dir)) { New-Item -ItemType Directory -Path $Dir -Force | Out-Null }
    $json = '{"id":"' + $Id + '","repo":"' + $Repo + '"}'
    $enc = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText((Join-Path $Dir '.periscope-download.json'), $json, $enc)
}

function Move-PeriscopeNestedLauncher {
    param([Parameter(Mandatory)][string]$Dir, [Parameter(Mandatory)][string]$BatName)
    $direct = Join-Path $Dir $BatName
    if (Test-Path -LiteralPath $direct) { return $true }
    if (-not (Test-Path -LiteralPath $Dir)) { return $false }
    $kids = @(Get-ChildItem -LiteralPath $Dir -Force | Where-Object { $_.Name -ne '.periscope-download.json' })
    if ($kids.Count -ne 1 -or -not $kids[0].PSIsContainer) { return $false }
    $inner = $kids[0].FullName
    foreach ($child in @(Get-ChildItem -LiteralPath $inner -Force)) {
        Move-Item -LiteralPath $child.FullName -Destination (Join-Path $Dir $child.Name) -Force
    }
    Remove-Item -LiteralPath $inner -Force
    Test-Path -LiteralPath $direct
}

function Expand-PeriscopeZip {
    param([Parameter(Mandatory)][string]$Zip, [Parameter(Mandatory)][string]$Dest, [Parameter(Mandatory)][string]$BatName)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if (-not (Test-Path -LiteralPath $Dest)) { New-Item -ItemType Directory -Path $Dest -Force | Out-Null }
    [IO.Compression.ZipFile]::ExtractToDirectory($Zip, $Dest)
    [bool](Move-PeriscopeNestedLauncher -Dir $Dest -BatName $BatName)
}

function Get-PeriscopeGangplankPlan {
    param([bool]$Running, [bool]$Configured, [bool]$Found, [string]$ReleaseUrl = '', [string]$ReleaseSha256 = '')
    if ($Running -and $Configured) { return [pscustomobject]@{ action = 'use'; step = ''; message = '' } }
    if ($Found -and $Configured -and -not $Running) { return [pscustomobject]@{ action = 'start'; step = 'token'; message = '' } }
    if ($Found -and -not $Configured) {
        return [pscustomobject]@{ action = 'walkthrough'; step = 'token'; message = 'Gangplank is installed, but it has no token yet. Open Launch-Gangplank.bat and add a token in Gangplank. This page does not ask for a token and will not download Gangplank again. Click Launch once the token is saved.' }
    }
    $urlOk = $ReleaseUrl -match '^https://\S+$'
    $shaOk = $ReleaseSha256 -match '^[0-9a-fA-F]{64}$'
    if ((-not $Found) -and $urlOk -and $shaOk) { return [pscustomobject]@{ action = 'download-gangplank'; step = ''; message = '' } }
    [pscustomobject]@{ action = 'walkthrough'; step = 'install'; message = 'Gangplank is how Periscope downloads utilities. It is not in the Periscope gangplank folder yet, and no pinned public release is recorded, so this page will not guess a download URL. Install Gangplank, start Launch-Gangplank.bat, and add a token in Gangplank. This page does not take a token. Click Launch again when Gangplank is ready.' }
}

function Get-PeriscopeCredential {
    param([Parameter(Mandatory)][string]$AppData)
    $token = [string]$env:GANGPLANK_TOKEN
    $store = Join-Path (Join-Path $AppData 'Gangplank') 'credential.dpapi'
    $hasStore = Test-Path -LiteralPath $store
    [pscustomobject]@{
        Configured = [bool]($token -or $hasStore)
        Token = $(if ($token) { $token } else { $null })
        UseStore = ((-not $token) -and $hasStore)
    }
}

function Test-PeriscopeGangplankListening {
    foreach ($port in $script:GangplankPorts) {
        $c = New-Object System.Net.Sockets.TcpClient
        try {
            $iar = $c.BeginConnect('127.0.0.1', $port, $null, $null)
            if (-not $iar.AsyncWaitHandle.WaitOne(300)) { continue }
            $c.EndConnect($iar)
            return $true
        } catch { } finally { $c.Close() }
    }
    $false
}

function Wait-PeriscopeReady {
    param([Parameter(Mandatory)][scriptblock]$Probe, [int]$TimeoutSec = 20)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ($true) {
        if (& $Probe) { return $true }
        if ((Get-Date) -ge $deadline) { return $false }
        Start-Sleep -Milliseconds 250
    }
}

function Test-PeriscopeLoopbackHost {
    # Listener prefix is http://127.0.0.1:<port>/ only (IPv4 loopback). localhost is accepted as that same bind's name.
    param([string]$HostHeader, [int]$Port)
    if (-not $HostHeader) { return $false }
    $h = $HostHeader.Trim()
    if ($h.Equals("127.0.0.1:$Port", [StringComparison]::Ordinal)) { return $true }
    if ($h.Equals("localhost:$Port", [StringComparison]::OrdinalIgnoreCase)) { return $true }
    $false
}

function Test-PeriscopeFetchSite {
    # Absent, same-origin, or none. Anything else must not receive the page token.
    param($Headers)
    $site = ''
    if ($Headers) {
        foreach ($k in @($Headers.Keys)) {
            if ([string]$k -ieq 'sec-fetch-site') { $site = [string]$Headers[$k]; break }
        }
    }
    if (-not $site) { return $true }
    $s = $site.Trim().ToLowerInvariant()
    return ($s -eq 'same-origin' -or $s -eq 'none')
}

function Get-PeriscopeChildEnvironment {
    # Explicit block for the Gangplank child. GANGPLANK_TOKEN is never copied; the child reads token.bin or its own store.
    param([hashtable]$Source)
    $keep = @('SystemRoot','windir','PATH','PATHEXT','TEMP','TMP','USERPROFILE','HOMEDRIVE','HOMEPATH','APPDATA','LOCALAPPDATA','USERNAME','USERDOMAIN','PROCESSOR_ARCHITECTURE','NUMBER_OF_PROCESSORS','OS','ComSpec')
    $out = @{}
    if (-not $Source) { return $out }
    foreach ($name in $keep) {
        foreach ($key in @($Source.Keys)) {
            if ([string]$key -eq 'GANGPLANK_TOKEN') { continue }
            if ([string]$key -ieq $name -and $Source[$key]) { $out[$name] = [string]$Source[$key]; break }
        }
    }
    if ($out.ContainsKey('GANGPLANK_TOKEN')) { $out.Remove('GANGPLANK_TOKEN') }
    $out
}

function Protect-PeriscopeToken {
    # CreateNew so a pre-created name or symlink fails. Owner-only ACL is set before the protected bytes are written.
    param([Parameter(Mandatory)][string]$Token, [Parameter(Mandatory)][string]$Path)
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $fs = New-Object IO.FileStream($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    $fs.Dispose()
    $windows = ($env:OS -eq 'Windows_NT')
    if ($windows) {
        $me = [Security.Principal.WindowsIdentity]::GetCurrent().User
        $acl = New-Object Security.AccessControl.FileSecurity
        $acl.SetOwner($me)
        $acl.SetAccessRuleProtection($true, $false)
        $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($me, 'FullControl', 'Allow')))
        [IO.File]::SetAccessControl($Path, $acl)
        Add-Type -AssemblyName System.Security
        $raw = [Text.Encoding]::UTF8.GetBytes($Token)
        $prot = [Security.Cryptography.ProtectedData]::Protect($raw, $null, 'CurrentUser')
        $bytes = $prot
    } else {
        & chmod 600 -- $Path
        if ($LASTEXITCODE -ne 0) { Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue; throw 'could not restrict token file' }
        $bytes = [Text.Encoding]::UTF8.GetBytes($Token)
    }
    $out = New-Object IO.FileStream($Path, [IO.FileMode]::Open, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $out.Write($bytes, 0, $bytes.Length) } finally { $out.Dispose() }
}

function Invoke-PeriscopeGangplankChild {
    param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][string]$Dest, [string]$Token, [string]$ModulePath, [switch]$UseStore)
    if ($Repo -notmatch '^https://github\.com/[\w.-]+/[\w.-]+/?$') { return @{ ok = $false; code = 'E_ARGS'; message = 'Repository URL is not a GitHub HTTPS URL.' } }
    if (-not $env:LOCALAPPDATA) { return @{ ok = $false; code = 'GANGPLANK_API'; message = 'LOCALAPPDATA is not set.' } }
    $tmpDir = Join-Path (Join-Path $env:LOCALAPPDATA 'Periscope\tokens') ([guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
    $tokenFile = Join-Path $tmpDir 'token.bin'
    $requestFile = Join-Path $tmpDir 'request.json'
    $resultFile = Join-Path $Dest '.periscope-gangplank-result.json'
    try {
        if ($Token) { Protect-PeriscopeToken -Token $Token -Path $tokenFile }
        $req = [ordered]@{ repo = $Repo; dest = $Dest; modulePath = [string]$ModulePath; tokenFile = $(if ($Token) { $tokenFile } else { '' }); useStore = [bool]$UseStore; resultFile = $resultFile }
        $enc = New-Object System.Text.UTF8Encoding($false)
        [IO.File]::WriteAllText($requestFile, ($req | ConvertTo-Json -Compress), $enc)
        $child = Join-Path $PSScriptRoot 'Invoke-GangplankChild.ps1'
        $exe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        if (-not (Test-Path -LiteralPath $exe)) { $exe = 'powershell.exe' }
        $arg = '-NoProfile -ExecutionPolicy Bypass -File "' + $child + '" -RequestFile "' + $requestFile + '"'
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $exe
        $psi.Arguments = $arg
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $inherited = @{}
        foreach ($key in @($psi.EnvironmentVariables.Keys)) { $inherited[[string]$key] = [string]$psi.EnvironmentVariables[$key] }
        $clean = Get-PeriscopeChildEnvironment -Source $inherited
        $psi.EnvironmentVariables.Clear()
        foreach ($key in @($clean.Keys)) { [void]$psi.EnvironmentVariables.Add([string]$key, [string]$clean[$key]) }
        $proc = New-Object System.Diagnostics.Process
        $proc.StartInfo = $psi
        [void]$proc.Start()
        $proc.WaitForExit()
        if (Test-Path -LiteralPath $resultFile) {
            $parsed = Get-Content -LiteralPath $resultFile -Raw | ConvertFrom-Json
            return @{ ok = [bool]$parsed.ok; code = [string]$parsed.code; message = [string]$parsed.message }
        }
        @{ ok = $false; code = 'GANGPLANK_API'; message = 'Gangplank child returned no result.' }
    } finally {
        if (Test-Path -LiteralPath $tokenFile) { Remove-Item -LiteralPath $tokenFile -Force -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $requestFile) { Remove-Item -LiteralPath $requestFile -Force -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $tmpDir) { Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

function Invoke-PeriscopePinnedDownload {
    param([string]$Url, [string]$Sha256, [Parameter(Mandatory)][string]$Dest)
    if ($Url -notmatch '^https://\S+$' -or $Sha256 -notmatch '^[0-9a-fA-F]{64}$') {
        return @{ ok = $false; code = 'NO_RELEASE'; message = 'No pinned Gangplank release is recorded.' }
    }
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N') + '.zip')
    try {
        $wc = New-Object System.Net.WebClient
        $wc.DownloadFile($Url, $tmp)
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $tmp).Hash
        if ($hash.ToLowerInvariant() -ne $Sha256.ToLowerInvariant()) {
            return @{ ok = $false; code = 'SHA_MISMATCH'; message = 'Gangplank release hash did not match the pin.' }
        }
        $ok = Expand-PeriscopeZip -Zip $tmp -Dest $Dest -BatName 'Launch-Gangplank.bat'
        if (-not $ok) { return @{ ok = $false; code = 'NO_LAUNCHER'; message = 'Downloaded, but no launcher found for Gangplank' } }
        @{ ok = $true; code = 'OK'; message = '' }
    } finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
}

function Invoke-PeriscopeLaunch {
    param(
        $Tool,
        [Parameter(Mandatory)][string]$AppData,
        [string]$ReleaseUrl = '',
        [string]$ReleaseSha256 = '',
        $Credential = $null,
        $Progress = $null
    )
    function Report([string]$State, [string]$Step) {
        if ($Progress -is [hashtable]) { $Progress['state'] = $State; $Progress['step'] = $Step; $Progress['tool'] = [string]$Tool.id }
    }
    if (-not (Test-PeriscopeLaunchable $Tool)) {
        return @{ ok = $false; code = 'NO_LAUNCHER'; message = 'Nothing to launch yet.'; state = 'error'; tool = [string]$Tool.id }
    }
    $batName = Get-PeriscopeLauncherName ([string]$Tool.launcher)
    $dir = Get-PeriscopeUtilityDir -AppData $AppData -Id ([string]$Tool.id)
    $bat = Join-Path $dir $batName
    Report 'checking' 'Checking'
    if (Test-Path -LiteralPath $bat) {
        & $script:DoStart $bat $dir
        Report 'launched' 'Launched'
        return @{ ok = $true; state = 'launched'; tool = [string]$Tool.id; message = 'Launched' }
    }
    $repo = [string]$Tool.repo
    if ($repo -notmatch '^https://github\.com/[\w.-]+/[\w.-]+/?$') {
        return @{ ok = $false; code = 'E_ARGS'; message = 'Repository URL is not a GitHub HTTPS URL.'; state = 'error'; tool = [string]$Tool.id }
    }
    $folder = Test-PeriscopeDownloadFolder -Dir $dir -Repo $repo -Id ([string]$Tool.id)
    if (-not $folder.ok) {
        return @{ ok = $false; code = 'FOLDER_EXISTS'; message = [string]$folder.message; state = 'error'; tool = [string]$Tool.id }
    }
    $gdir = Get-PeriscopeUtilityDir -AppData $AppData -Id 'gangplank'
    $gbat = Join-Path $gdir 'Launch-Gangplank.bat'
    $found = Test-Path -LiteralPath $gbat
    $running = [bool](& $script:DoProbe)
    if (-not $Credential) { $Credential = Get-PeriscopeCredential -AppData $AppData }
    if (-not $ReleaseUrl) { $ReleaseUrl = $script:GangplankReleaseUrl }
    if (-not $ReleaseSha256) { $ReleaseSha256 = $script:GangplankReleaseSha256 }
    $plan = Get-PeriscopeGangplankPlan -Running:$running -Configured:([bool]$Credential.Configured) -Found:$found -ReleaseUrl $ReleaseUrl -ReleaseSha256 $ReleaseSha256
    if ($plan.action -eq 'download-gangplank') {
        Report 'downloading' 'Downloading Gangplank'
        $dl = & $script:DoDownload $ReleaseUrl $ReleaseSha256 $gdir
        if (-not $dl.ok) { return @{ ok = $false; code = [string]$dl.code; message = [string]$dl.message; state = 'error'; tool = [string]$Tool.id } }
        $found = Test-Path -LiteralPath $gbat
        if (-not $found) { return @{ ok = $false; code = 'NO_LAUNCHER'; message = 'Downloaded, but no launcher found for Gangplank'; state = 'error'; tool = [string]$Tool.id } }
        $running = [bool](& $script:DoProbe)
        $plan = Get-PeriscopeGangplankPlan -Running:$running -Configured:([bool]$Credential.Configured) -Found:$true -ReleaseUrl '' -ReleaseSha256 ''
    }
    if ($plan.action -eq 'walkthrough') {
        Report 'walkthrough' 'Gangplank setup'
        return @{ ok = $true; state = 'walkthrough'; step = [string]$plan.step; message = [string]$plan.message; tool = [string]$Tool.id }
    }
    if ($plan.action -eq 'start') {
        Report 'starting' 'Starting Gangplank'
        if (-not $running) { & $script:DoStart $gbat $gdir }
        if (-not (Wait-PeriscopeReady -Probe $script:DoProbe -TimeoutSec 20)) {
            return @{ ok = $false; code = 'GANGPLANK_TIMEOUT'; message = 'Gangplank did not respond in time.'; state = 'error'; tool = [string]$Tool.id }
        }
    }
    Write-PeriscopeMarker -Dir $dir -Repo $repo -Id ([string]$Tool.id)
    $module = Join-Path $gdir 'Gangplank.psm1'
    Report 'downloading' 'Downloading'
    $gr = & $script:DoGangplank $repo $dir ([string]$Credential.Token) $module ([bool]$Credential.UseStore)
    if (-not $gr -or -not $gr.ok) {
        $code = 'GANGPLANK_API'; $message = 'Gangplank could not download the utility.'
        if ($gr) { if ($gr.code) { $code = [string]$gr.code }; if ($gr.message) { $message = [string]$gr.message } }
        return @{ ok = $false; code = $code; message = $message; state = 'error'; tool = [string]$Tool.id }
    }
    Report 'verifying' 'Verifying'
    [void](Move-PeriscopeNestedLauncher -Dir $dir -BatName $batName)
    if (-not (Test-Path -LiteralPath $bat)) {
        return @{ ok = $false; code = 'NO_LAUNCHER'; message = ('Downloaded, but no launcher found for ' + [string]$Tool.name); state = 'error'; tool = [string]$Tool.id }
    }
    Report 'launching' 'Launching'
    & $script:DoStart $bat $dir
    Report 'launched' 'Launched'
    @{ ok = $true; state = 'launched'; tool = [string]$Tool.id; message = 'Launched' }
}

function Get-PeriscopeStatusResult {
    param($Tool, [string]$AppData = '')
    $result = [ordered]@{ local = $true; tool = $null; launchable = $false; present = $false }
    if ($Tool) {
        $result.tool = [string]$Tool.id
        $result.launchable = [bool](Test-PeriscopeLaunchable $Tool)
        if ($result.launchable) {
            $result.launcher = Get-PeriscopeLauncherName ([string]$Tool.launcher)
            if ($AppData) {
                $bat = Join-Path (Get-PeriscopeUtilityDir -AppData $AppData -Id ([string]$Tool.id)) ([string]$result.launcher)
                $result.present = Test-Path -LiteralPath $bat
            }
        } else {
            $result.reason = $(if ([string]$Tool.group -eq 'support') { 'support' } else { 'no-launcher' })
        }
    }
    [pscustomobject]$result
}

function Get-PeriscopeDownloadStatus {
    param($Jobs, [string]$JobId)
    if (-not $Jobs -or $JobId -notmatch '^job_[0-9a-f]{32}$' -or -not $Jobs.ContainsKey($JobId)) {
        return New-PeriscopeEnvelope 'periscope download-status' -Code E_NOTFOUND -Message 'unknown job'
    }
    New-PeriscopeEnvelope 'periscope download-status' -Result $Jobs[$JobId]
}

function Add-PeriscopeTokenMeta {
    param([Parameter(Mandatory)][string]$Html, [Parameter(Mandatory)][string]$Token)
    if ($Token -notmatch '^[0-9a-f]{64}$') { throw 'session token must be 64 hex characters' }
    $meta = '<meta name="periscope-token" content="' + $Token + '">'
    if ($Html -notmatch '<head>') { throw 'index.html has no head' }
    $Html.Replace('<head>', '<head>' + $meta)
}

function Resolve-PeriscopeStatic {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$UrlPath)
    $rel = $UrlPath
    if ($rel -eq '' -or $rel -eq '/') { $rel = 'index.html' } else { $rel = $rel.TrimStart('/') }
    $rel = $rel.Replace('/', [IO.Path]::DirectorySeparatorChar)
    if ($rel -match '\.\.' -or $rel -match '^[A-Za-z]:') { return $null }
    $leafOk = ($rel -eq 'index.html' -or $rel -eq 'catalog.json' -or $rel.StartsWith('assets' + [IO.Path]::DirectorySeparatorChar) -or $rel.StartsWith('ui-kit' + [IO.Path]::DirectorySeparatorChar))
    if (-not $leafOk) { return $null }
    $rootFull = [IO.Path]::GetFullPath($Root)
    if (-not $rootFull.EndsWith([IO.Path]::DirectorySeparatorChar)) { $rootFull = $rootFull + [IO.Path]::DirectorySeparatorChar }
    $full = [IO.Path]::GetFullPath((Join-Path $Root $rel))
    if (-not $full.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)) { return $null }
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { return $null }
    $full
}

Export-ModuleMember -Function Enable-PeriscopeRuntime, Set-PeriscopeBoundary, Reset-PeriscopeBoundary, New-PeriscopeEnvelope, Test-PeriscopeToolId,
    Get-PeriscopeLauncherName, Test-PeriscopeLaunchable, Get-PeriscopeCatalogTool, Get-PeriscopeUtilityDir,
    Test-PeriscopeDownloadFolder, Move-PeriscopeNestedLauncher, Expand-PeriscopeZip, Get-PeriscopeGangplankPlan,
    Invoke-PeriscopeLaunch, Get-PeriscopeStatusResult, Get-PeriscopeDownloadStatus, Add-PeriscopeTokenMeta, Resolve-PeriscopeStatic,
    Test-PeriscopeLoopbackHost, Test-PeriscopeFetchSite, Get-PeriscopeChildEnvironment,
    Invoke-PeriscopePinnedDownload, Write-PeriscopeMarker
