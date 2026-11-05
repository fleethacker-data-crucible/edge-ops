# Periscope local host. Windows PowerShell 5.1 only. Loopback only. No admin.
# Serves index.html, assets/, catalog.json and ui-kit/ from the edge-ops repo root.
# Bind is IPv4 loopback only: http://127.0.0.1:<port>/.
# Host 127.0.0.1:<port> or localhost:<port> is accepted. localhost is only the name for that IPv4 bind.
# Any other Host is rejected on every response, before a page token is written.
#   powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File tools\periscope\Periscope.ps1 [-Port n] [-NoBrowser] [-CheckOnly]
param([int]$Port = 0, [switch]$NoBrowser, [switch]$CheckOnly)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2

if ($PSVersionTable.PSVersion.Major -ne 5) { throw "Run with Windows PowerShell 5.1 (powershell.exe), not $($PSVersionTable.PSVersion)." }

$here = $PSScriptRoot
$repo = Split-Path -Parent (Split-Path -Parent $here)
$versionFile = Join-Path $here 'VERSION'
$version = if (Test-Path -LiteralPath $versionFile) { (Get-Content -LiteralPath $versionFile -Raw).Trim() } else { '0.1.0' }
$catalogPath = Join-Path $repo 'catalog.json'

Import-Module (Join-Path $here 'Periscope.psm1') -Force
Import-Module (Join-Path $repo 'tools\fleet-port\FleetPort.psm1') -Force
Import-Module (Join-Path $repo 'tools\fleet-action\FleetAction.psm1') -Force

$logDir = Join-Path $env:LOCALAPPDATA 'Periscope\logs'
if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$logFile = Join-Path $logDir ('Periscope_{0:yyyy_MM_dd_HHmmss}.log' -f (Get-Date))
function Write-PeriscopeLog([string]$Action, [string]$Tool, [string]$Status) {
    $line = '{0:yyyy-MM-dd HH:mm:ss}  [INFO] {1} tool={2} status={3}' -f (Get-Date), $Action, $Tool, $Status
    try { [IO.File]::AppendAllText($logFile, $line + "`r`n") } catch { }
}

if ($CheckOnly) {
    if (-not (Test-Path -LiteralPath $catalogPath)) { throw 'catalog.json is missing' }
    $block = Get-FleetPortBlock -Tool 'periscope'
    if ($block.Start -ne 8803 -or $block.Size -ne 3) { throw 'Periscope port block is not 8803-8805' }
    Write-PeriscopeLog 'check' 'periscope' 'ok'
    Write-Host 'Self-check passed.'
    exit 0
}

Enable-PeriscopeRuntime
$resolved = Resolve-FleetPort -Tool 'periscope' -Version $version -NoListener
if ($Port -gt 0) {
    $listener = New-FleetHttpListener -Port $Port
    Assert-FleetListenerPrefix $listener
    $listener.Start()
    $actual = $Port
} elseif ($resolved.Action -eq 'Reuse') {
    Write-PeriscopeLog 'port' 'periscope' ('reuse ' + $resolved.Port)
    if (-not $NoBrowser) { Start-Process $resolved.Url }
    exit 0
} else {
    $listener = New-FleetHttpListener -Port $resolved.Port
    Assert-FleetListenerPrefix $listener
    $listener.Start()
    $actual = $resolved.Port
}

$token = New-FleetSessionToken -App 'periscope'
$jobs = [hashtable]::Synchronized(@{})
$workers = New-Object System.Collections.Generic.List[object]
Write-PeriscopeLog 'listen' 'periscope' ('127.0.0.1:' + $actual)

function Send-PeriscopeBytes($Context, [int]$Status, [byte[]]$Bytes, [string]$ContentType) {
    $res = $Context.Response
    $res.StatusCode = $Status
    $res.ContentType = $ContentType
    $res.Headers['Cache-Control'] = 'no-store'
    $res.Headers['X-Content-Type-Options'] = 'nosniff'
    $res.Headers['X-Frame-Options'] = 'DENY'
    $res.Headers['Content-Security-Policy'] = "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self'; font-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'"
    $res.ContentLength64 = $Bytes.Length
    if ($Bytes.Length -gt 0) { $res.OutputStream.Write($Bytes, 0, $Bytes.Length) }
    $res.Close()
}
function Send-PeriscopeJson($Context, [int]$Status, $Obj) {
    $json = $Obj | ConvertTo-Json -Depth 8 -Compress
    Send-PeriscopeBytes $Context $Status ([Text.Encoding]::UTF8.GetBytes($json)) 'application/json; charset=utf-8'
}
function Get-QueryValue([string]$Query, [string]$Key) {
    $q = [string]$Query
    if ($q.StartsWith('?')) { $q = $q.Substring(1) }
    foreach ($pair in ($q -split '&')) {
        if (-not $pair) { continue }
        $kv = $pair -split '=', 2
        $name = [Uri]::UnescapeDataString($kv[0])
        if ($name -eq $Key) {
            if ($kv.Count -lt 2) { return '' }
            return [Uri]::UnescapeDataString($kv[1])
        }
    }
    ''
}
function Get-HeaderMap($Request) {
    $h = @{}
    foreach ($k in @($Request.Headers.AllKeys)) { if ($k) { $h[$k] = [string]$Request.Headers[$k] } }
    $h
}

if (-not $NoBrowser) { Start-Process ('http://127.0.0.1:' + $actual + '/') }
try {
    while ($listener.IsListening) {
        $ctx = $listener.GetContext()
        $req = $ctx.Request
        $headers = Get-HeaderMap $req
        if (-not (Test-PeriscopeLoopbackHost -HostHeader ([string]$req.Headers['Host']) -Port $actual)) {
            Send-PeriscopeBytes $ctx 403 (New-Object byte[] 0) 'text/plain; charset=utf-8'
            continue
        }
        $fleet = Invoke-FleetIdEndpoint -Context $ctx -Tool 'periscope' -Version $version -Path $PSCommandPath
        if ($fleet -eq 'shutdown') { $listener.Stop(); break }
        if ($fleet) { continue }
        $bad = Test-FleetHttpAuth $headers $actual $token
        $path = $req.Url.AbsolutePath
        $isApi = $path.StartsWith('/api/periscope/')
        if ($isApi) {
            if ($bad -like 'FORBIDDEN:*') { Send-PeriscopeJson $ctx 403 (New-FleetEnvelope 'periscope' -Code E_FORBIDDEN -Message $bad.Substring(10)); continue }
            if ($bad) { Send-PeriscopeJson $ctx 401 (New-FleetEnvelope 'periscope' -Code E_AUTH -Message $bad); continue }
        }
        if ($path -eq '/api/periscope/status' -and $req.HttpMethod -eq 'GET') {
            $tool = $null
            $id = Get-QueryValue $req.Url.Query 'tool'
            if ($id) {
                if (-not (Test-PeriscopeToolId $id)) { Send-PeriscopeJson $ctx 400 (New-FleetEnvelope 'periscope status' -Code E_ARGS -Message 'bad tool id'); continue }
                $tool = Get-PeriscopeCatalogTool -CatalogPath $catalogPath -Id $id
                if (-not $tool) { Send-PeriscopeJson $ctx 404 (New-FleetEnvelope 'periscope status' -Code E_NOTFOUND -Message 'unknown tool'); continue }
            }
            $result = Get-PeriscopeStatusResult -Tool $tool -AppData $env:LOCALAPPDATA
            Send-PeriscopeJson $ctx 200 (New-FleetEnvelope 'periscope status' -Result $result)
            continue
        }
        if ($path -eq '/api/periscope/download-status' -and $req.HttpMethod -eq 'GET') {
            $job = Get-QueryValue $req.Url.Query 'job'
            $status = Get-PeriscopeDownloadStatus -Jobs $jobs -JobId $job
            $http = 200
            if (-not $status.ok) { $http = 404 }
            Send-PeriscopeJson $ctx $http $status
            continue
        }
        if ($path -eq '/api/periscope/launch' -and $req.HttpMethod -eq 'POST') {
            $len = $req.ContentLength64
            if ($len -lt 0) { Send-PeriscopeJson $ctx 411 (New-FleetEnvelope 'periscope launch' -Code E_LENGTH -Message 'Content-Length required'); continue }
            $text = Read-FleetBoundedBody $req.InputStream $len
            try { $body = $text | ConvertFrom-Json } catch { Send-PeriscopeJson $ctx 400 (New-FleetEnvelope 'periscope launch' -Code E_ARGS -Message 'body is not JSON'); continue }
            $id = [string]$body.tool
            if (-not (Test-PeriscopeToolId $id)) { Send-PeriscopeJson $ctx 400 (New-FleetEnvelope 'periscope launch' -Code E_ARGS -Message 'bad tool id'); continue }
            $tool = Get-PeriscopeCatalogTool -CatalogPath $catalogPath -Id $id
            if (-not $tool) { Send-PeriscopeJson $ctx 404 (New-FleetEnvelope 'periscope launch' -Code E_NOTFOUND -Message 'unknown tool'); continue }
            if (-not (Test-PeriscopeLaunchable $tool)) { Send-PeriscopeJson $ctx 200 (New-FleetEnvelope 'periscope launch' -Code NO_LAUNCHER -Message 'Nothing to launch yet.'); continue }
            $job = 'job_' + [guid]::NewGuid().ToString('N')
            $bag = [hashtable]::Synchronized(@{ job = $job; tool = $id; state = 'checking'; step = 'Checking'; percent = $null; message = ''; ok = $true; code = '' })
            $jobs[$job] = $bag
            Write-PeriscopeLog 'launch' $id 'checking'
            $rs = [runspacefactory]::CreateRunspace()
            $rs.Open()
            $rs.SessionStateProxy.SetVariable('PeriscopeJob', $bag)
            $ps = [powershell]::Create()
            $ps.Runspace = $rs
            [void]$ps.AddScript({
                param($mod, $toolId, $appData, $cat)
                Import-Module $mod -Force
                Enable-PeriscopeRuntime
                $tool = Get-PeriscopeCatalogTool -CatalogPath $cat -Id $toolId
                $r = Invoke-PeriscopeLaunch -Tool $tool -AppData $appData -Progress $PeriscopeJob
                $PeriscopeJob['ok'] = [bool]$r.ok
                $PeriscopeJob['state'] = [string]$r.state
                if ($r.message) { $PeriscopeJob['message'] = [string]$r.message }
                if ($r.code) { $PeriscopeJob['code'] = [string]$r.code }
                if ($r.step) { $PeriscopeJob['step'] = [string]$r.step }
            }).AddArgument((Join-Path $here 'Periscope.psm1')).AddArgument($id).AddArgument($env:LOCALAPPDATA).AddArgument($catalogPath)
            [void]$ps.BeginInvoke()
            $workers.Add($ps)
            Send-PeriscopeJson $ctx 200 (New-FleetEnvelope 'periscope launch' -Result ([ordered]@{ job = $job; tool = $id; state = 'checking'; step = 'Checking' }))
            continue
        }
        if ($isApi) { Send-PeriscopeJson $ctx 404 (New-FleetEnvelope 'periscope' -Code E_NOTFOUND -Message 'no such route'); continue }
        if ($req.HttpMethod -ne 'GET') { Send-PeriscopeBytes $ctx 405 (New-Object byte[] 0) 'text/plain; charset=utf-8'; continue }
        $file = Resolve-PeriscopeStatic -Root $repo -UrlPath $path
        if (-not $file) { Send-PeriscopeBytes $ctx 404 (New-Object byte[] 0) 'text/plain; charset=utf-8'; continue }
        $bytes = [IO.File]::ReadAllBytes($file)
        $ext = [IO.Path]::GetExtension($file).ToLowerInvariant()
        $type = 'application/octet-stream'
        switch ($ext) {
            '.html' { $type = 'text/html; charset=utf-8' }
            '.css' { $type = 'text/css; charset=utf-8' }
            '.js' { $type = 'text/javascript; charset=utf-8' }
            '.json' { $type = 'application/json; charset=utf-8' }
            '.svg' { $type = 'image/svg+xml' }
            '.png' { $type = 'image/png' }
            '.webp' { $type = 'image/webp' }
            '.woff' { $type = 'font/woff' }
            '.woff2' { $type = 'font/woff2' }
        }
        if ($ext -eq '.html' -and [IO.Path]::GetFileName($file) -eq 'index.html') {
            if (-not (Test-PeriscopeFetchSite -Headers $headers)) {
                Send-PeriscopeBytes $ctx 403 (New-Object byte[] 0) 'text/plain; charset=utf-8'
                continue
            }
            $html = Add-PeriscopeTokenMeta -Html ([Text.Encoding]::UTF8.GetString($bytes)) -Token $token
            $bytes = [Text.Encoding]::UTF8.GetBytes($html)
        }
        Send-PeriscopeBytes $ctx 200 $bytes $type
    }
} finally {
    if ($listener) { $listener.Close() }
    Remove-FleetSessionToken -App 'periscope'
}
