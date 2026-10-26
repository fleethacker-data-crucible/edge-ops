<#
.SYNOPSIS
    Pester 5 tests for FleetTestHarness (isolated Chrome + leases). Uses a private lock root via $env:FLEET_LOCK_ROOT.
#>
BeforeAll {
    Set-StrictMode -Version Latest
    $script:Here = Split-Path -Parent $PSScriptRoot
    $script:Mod = Join-Path $script:Here 'FleetTestHarness.psm1'
    $env:FLEET_LOCK_ROOT = Join-Path $env:TEMP ('fleetlocks-test-' + [guid]::NewGuid().ToString('N').Substring(0,8))
    New-Item -ItemType Directory -Path $env:FLEET_LOCK_ROOT -Force | Out-Null
    Import-Module $script:Mod -Force
    function Start-Ps([string]$code) {
        $f = Join-Path $env:TEMP ('fth-' + [guid]::NewGuid().ToString('N') + '.ps1')
        $pre = "`$env:FLEET_LOCK_ROOT='$env:FLEET_LOCK_ROOT'; Import-Module '$script:Mod' -Force; "
        Set-Content -Path $f -Value ($pre + $code) -Encoding UTF8
        $out = $f + '.out'
        $p = Start-Process powershell.exe -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',$f -RedirectStandardOutput $out -PassThru -WindowStyle Hidden
        [pscustomobject]@{ Proc = $p; Out = $out }
    }
    function Write-StaleLock([string]$res, [int]$deadPid, [int]$ageMin) {
        $hb = [DateTime]::UtcNow.AddMinutes(-$ageMin).ToString('o')
        $j = @{ resource=$res; owner='ghost'; pid=$deadPid; host=$env:COMPUTERNAME; acquired=$hb; heartbeat=$hb; token='ghost' } | ConvertTo-Json -Compress
        [IO.File]::WriteAllText((Join-Path $env:FLEET_LOCK_ROOT "$res.json"), $j)
    }
}
AfterAll { Remove-Item -LiteralPath $env:FLEET_LOCK_ROOT -Recurse -Force -ErrorAction SilentlyContinue; Remove-Item Env:\FLEET_LOCK_ROOT -ErrorAction SilentlyContinue }

Describe 'Isolated Chrome' {
    It 'runs two instances concurrently from separate processes with distinct ports/PIDs/profiles' {
        $runs = 1..2 | ForEach-Object {
            Start-Ps "Start-IsolatedChrome -Agent pester$_ -Headless | ConvertTo-Json -Compress"
        }
        $runs | ForEach-Object { $_.Proc.WaitForExit(60000) | Out-Null }
        $inst = $runs | ForEach-Object { (Get-Content $_.Out -Raw) | ConvertFrom-Json }
        try {
            @($inst).Count | Should -Be 2
            $inst[0].Port | Should -Not -Be $inst[1].Port
            $inst[0].Pid | Should -Not -Be $inst[1].Pid
            $inst[0].ProfilePath | Should -Not -Be $inst[1].ProfilePath
            foreach ($i in $inst) {
                $i.Port | Should -BeGreaterOrEqual 9300; $i.Port | Should -BeLessOrEqual 9399
                (Invoke-RestMethod "http://127.0.0.1:$($i.Port)/json/version" -TimeoutSec 5).Browser | Should -Match 'Chrome'
            }
        } finally {
            foreach ($i in $inst) { $r = Stop-IsolatedChrome $i; $r.ProfileDeleted | Should -BeTrue }
        }
        foreach ($i in $inst) {
            Test-Path $i.ProfilePath | Should -BeFalse
            @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" | Where-Object { $_.CommandLine -like "*$($i.ProfilePath)*" }).Count | Should -Be 0
        }
    }
}

Describe 'Leases' {
    It 'contention: B times out while A holds, then acquires after release' {
        $a = Start-Ps "`$l = Enter-FleetLock desktop-focus -Owner A; 'held'; Start-Sleep 16; Exit-FleetLock `$l | Out-Null; 'released'"
        Start-Sleep 3
        (Get-FleetLocks | Where-Object Resource -eq 'desktop-focus').Owner | Should -Be 'A'
        { Enter-FleetLock desktop-focus -Owner B -TimeoutSec 10 } | Should -Throw '*Timed out*'
        $b = Enter-FleetLock desktop-focus -Owner B -TimeoutSec 30
        $b.Owner | Should -Be 'B'
        Exit-FleetLock $b | Should -BeTrue
        $a.Proc.WaitForExit(30000) | Out-Null
    }
    It 'stale takeover via dead PID' {
        Write-StaleLock 'gpu' 999999 0
        (Get-FleetLocks | Where-Object Resource -eq 'gpu').IsStale | Should -BeTrue
        $l = Enter-FleetLock gpu -Owner taker
        $l.Owner | Should -Be 'taker'
        Exit-FleetLock $l | Should -BeTrue
    }
    It 'stale takeover via old heartbeat (live PID, 6 min old)' {
        Write-StaleLock 'outlook-com' $PID 6
        $l = Enter-FleetLock outlook-com -Owner taker2
        $l.Owner | Should -Be 'taker2'
        Exit-FleetLock $l | Out-Null
    }
    It 'race: exactly one of two takers wins a stale lock' {
        Write-StaleLock 'port-9999' 999999 10
        $go = (Get-Date).AddSeconds(4).ToString('o')
        $code = "while((Get-Date) -lt [DateTime]::Parse('$go')){Start-Sleep -Milliseconds 5}; try { `$l = Enter-FleetLock port-9999 -Owner `$PID -TimeoutSec 0; 'WIN'; Start-Sleep 5 } catch { 'LOSE' }"
        $r = 1..2 | ForEach-Object { Start-Ps $code }
        $r | ForEach-Object { $_.Proc.WaitForExit(30000) | Out-Null }
        $res = $r | ForEach-Object { (Get-Content $_.Out -Raw).Trim() }
        @($res | Where-Object { $_ -eq 'WIN' }).Count | Should -Be 1
        @($res | Where-Object { $_ -eq 'LOSE' }).Count | Should -Be 1
    }
    It 'Update-FleetLock renews heartbeat; background heartbeat renews too' {
        $l = Enter-FleetLock hb-test
        $h1 = (Get-Content $l.Path -Raw | ConvertFrom-Json).heartbeat
        Start-Sleep -Milliseconds 1100
        Update-FleetLock $l | Should -BeTrue
        $h2 = (Get-Content $l.Path -Raw | ConvertFrom-Json).heartbeat
        $h2 | Should -Not -Be $h1
        Start-FleetLockHeartbeat -Lock $l -IntervalSec 2 | Out-Null
        Start-Sleep 7
        $h3 = (Get-Content $l.Path -Raw | ConvertFrom-Json).heartbeat
        $h3 | Should -Not -Be $h2
        Exit-FleetLock $l | Should -BeTrue
    }
    It 'release refuses a foreign handle' {
        $l = Enter-FleetLock own-test
        $fake = [pscustomobject]@{ Resource='own-test'; Path=$l.Path; Token='nope'; HeartbeatJob=$null }
        Exit-FleetLock $fake -WarningAction SilentlyContinue | Should -BeFalse
        Test-Path $l.Path | Should -BeTrue
        Exit-FleetLock $l | Should -BeTrue
    }
}
