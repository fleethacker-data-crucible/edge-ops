# Gangplank child process. Never dot-source this into the Periscope host.
# The host passes a request file. A GitHub token, when present, is a DPAPI blob beside it and is deleted here.
param([Parameter(Mandatory)][string]$RequestFile)
$ErrorActionPreference = 'Stop'
$token = $null
$resultFile = ''
$tokenFile = ''
function Write-Result([bool]$Ok, [string]$Code, [string]$Message) {
    if (-not $resultFile) { return }
    $dir = Split-Path -Parent $resultFile
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $json = '{"ok":' + $(if ($Ok) { 'true' } else { 'false' }) + ',"code":"' + $Code + '","message":"' + ($Message -replace '"', '''') + '"}'
    $enc = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($resultFile, $json, $enc)
}
try {
    $req = Get-Content -LiteralPath $RequestFile -Raw | ConvertFrom-Json
    $resultFile = [string]$req.resultFile
    $tokenFile = [string]$req.tokenFile
    $modulePath = [string]$req.modulePath
    if (-not $modulePath -or -not (Test-Path -LiteralPath $modulePath)) { Write-Result $false 'GANGPLANK_MISSING' 'Gangplank module was not found.'; exit 2 }
    if ($tokenFile -and (Test-Path -LiteralPath $tokenFile)) {
        Add-Type -AssemblyName System.Security
        $prot = [IO.File]::ReadAllBytes($tokenFile)
        $raw = [Security.Cryptography.ProtectedData]::Unprotect($prot, $null, 'CurrentUser')
        $token = [Text.Encoding]::UTF8.GetString($raw)
    } elseif (-not [bool]$req.useStore) {
        Write-Result $false 'NO_TOKEN' 'Gangplank has no token.'
        exit 2
    }
    Import-Module -LiteralPath $modulePath -Force
    $cmd = Get-Command Open-GangplankRepository -ErrorAction SilentlyContinue
    if (-not $cmd) { Write-Result $false 'GANGPLANK_API' 'Gangplank has no Open-GangplankRepository command.'; exit 2 }
    $bound = @{}
    foreach ($name in @($cmd.Parameters.Keys)) {
        switch -Regex ($name) {
            '^(Repo|Repository|Url)$' { $bound[$name] = [string]$req.repo }
            '^(Dest|Destination|Path|WorkRoot|Workroot)$' { $bound[$name] = [string]$req.dest }
            '^(Token|AccessToken)$' { if ($token) { $bound[$name] = $token } }
        }
    }
    if ($bound.Count -lt 1) { Write-Result $false 'GANGPLANK_API' 'Gangplank parameters were not recognized.'; exit 2 }
    & $cmd @bound | Out-Null
    Write-Result $true 'OK' 'Downloaded'
    exit 0
} catch {
    $code = 'GANGPLANK_API'
    $msg = $_.Exception.Message
    foreach ($known in @('AUTH_REJECTED', 'FORBIDDEN', 'NOT_FOUND', 'RATE_LIMITED')) {
        if ($msg -match $known) { $code = $known; $msg = $known; break }
    }
    if ($code -eq 'GANGPLANK_API') { $msg = 'Gangplank could not download the repository.' }
    Write-Result $false $code $msg
    exit 1
} finally {
    $token = $null
    if ($tokenFile -and (Test-Path -LiteralPath $tokenFile)) { Remove-Item -LiteralPath $tokenFile -Force -ErrorAction SilentlyContinue }
}
