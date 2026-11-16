# Pester 5. Runs on Windows PowerShell 5.1 and pwsh. The listener is 127.0.0.1 only.
BeforeAll {
    Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'SpeechIn.psm1') -Force

    function New-Wav([string]$Path) {
        $pcm = New-Object byte[] 32
        $fs = [System.IO.File]::Create($Path)
        try {
            $bw = New-Object System.IO.BinaryWriter($fs)
            $bw.Write([Text.Encoding]::ASCII.GetBytes('RIFF'))
            $bw.Write([int](36 + $pcm.Length))
            $bw.Write([Text.Encoding]::ASCII.GetBytes('WAVEfmt '))
            $bw.Write([int]16); $bw.Write([int16]1); $bw.Write([int16]1)
            $bw.Write([int]8000); $bw.Write([int]16000); $bw.Write([int16]2); $bw.Write([int16]16)
            $bw.Write([Text.Encoding]::ASCII.GetBytes('data'))
            $bw.Write([int]$pcm.Length)
            $bw.Write($pcm)
            $bw.Dispose()
        }
        finally { $fs.Dispose() }
    }

    function Start-FakeSpeech([string]$Mode, [string]$Key, [string]$Tool = 'fairlead', [int]$ReportedPid = -1, [string]$ReportedPath = '') {
        if ($ReportedPid -lt 0) { $ReportedPid = $PID }
        if (-not $ReportedPath) { $ReportedPath = (Get-Process -Id $PID).Path }
        $tcp = New-Object System.Net.Sockets.TcpListener ([System.Net.IPAddress]::Loopback, 0)
        $tcp.Start()
        $port = ([System.Net.IPEndPoint]$tcp.LocalEndpoint).Port
        $tcp.Stop()
        $hits = Join-Path ([System.IO.Path]::GetTempPath()) ('speechhits-' + [guid]::NewGuid().ToString('N'))
        $log = $hits + '.log'
        [System.IO.File]::WriteAllText($hits, '0')
        [System.IO.File]::WriteAllText($log, '')
        $ps = [PowerShell]::Create()
        [void]$ps.AddScript({
            param($Port, $Mode, $Key, $Hits, $Log, $Tool, $ReportedPid, $ReportedPath)
            $l = New-Object System.Net.HttpListener
            $l.Prefixes.Add("http://127.0.0.1:$Port/")
            $l.Start()
            try {
                for ($i = 0; $i -lt 2; $i++) {
                    $async = $l.BeginGetContext($null, $null)
                    if (-not $async.AsyncWaitHandle.WaitOne(1500)) { break }
                    $ctx = $l.EndGetContext($async)
                    $n = 0
                    if (Test-Path -LiteralPath $Hits) { $n = [int]([System.IO.File]::ReadAllText($Hits)) }
                    [System.IO.File]::WriteAllText($Hits, ([string]($n + 1)))
                    $auth = [string]$ctx.Request.Headers['Authorization']
                    $flag = '0'; if ($auth) { $flag = '1' }
                    [System.IO.File]::AppendAllText($Log, ($ctx.Request.Url.AbsolutePath + ' auth=' + $flag + "`n"))
                    $res = $ctx.Response
                    if ($ctx.Request.Url.AbsolutePath -eq '/__fleethacker/id') {
                        $body = '{"tool":"' + $Tool + '","version":"1.0.0","pid":' + $ReportedPid + ',"path":"' + ($ReportedPath -replace '\\', '\\') + '"}'
                        $bytes = [Text.Encoding]::UTF8.GetBytes($body)
                        $res.StatusCode = 200
                        $res.ContentType = 'application/json'
                        $res.OutputStream.Write($bytes, 0, $bytes.Length)
                        $res.Close()
                        continue
                    }
                    if ($Mode -eq 'redirect') {
                        $res.StatusCode = 302
                        $res.RedirectLocation = 'http://example.invalid/v1/audio/transcriptions'
                    }
                    elseif ($Mode -eq 'echo-key') {
                        $res.StatusCode = 500
                        $bytes = [Text.Encoding]::UTF8.GetBytes($Key)
                        $res.OutputStream.Write($bytes, 0, $bytes.Length)
                    }
                    elseif ($auth -ne ('Bearer ' + $Key)) {
                        $res.StatusCode = 401
                    }
                    else {
                        $res.StatusCode = 200
                        $res.ContentType = 'application/json'
                        $bytes = [Text.Encoding]::UTF8.GetBytes('{"text":"hello fleet"}')
                        $res.OutputStream.Write($bytes, 0, $bytes.Length)
                    }
                    $res.Close()
                }
            }
            finally { $l.Close() }
        }).AddArgument($port).AddArgument($Mode).AddArgument($Key).AddArgument($hits).AddArgument($log).AddArgument($Tool).AddArgument($ReportedPid).AddArgument($ReportedPath)
        $handle = $ps.BeginInvoke()
        Start-Sleep -Milliseconds 300
        [pscustomobject]@{ Port = $port; Handle = $handle; PowerShell = $ps; Hits = $hits; Log = $log }
    }
}

Describe 'Test-SpeechInEndpoint' {
    It 'accepts only the loopback transcription URL' {
        Test-SpeechInEndpoint 'http://127.0.0.1:8776/v1/audio/transcriptions' | Should -BeTrue
        Test-SpeechInEndpoint 'http://localhost:8776/v1/audio/transcriptions' | Should -BeTrue
        Test-SpeechInEndpoint 'https://127.0.0.1:8776/v1/audio/transcriptions' | Should -BeFalse
        Test-SpeechInEndpoint 'http://example.invalid/v1/audio/transcriptions' | Should -BeFalse
        Test-SpeechInEndpoint 'http://127.0.0.1:8776/v1/audio/speech' | Should -BeFalse
        Test-SpeechInEndpoint 'http://user:pw@127.0.0.1:8776/v1/audio/transcriptions' | Should -BeFalse
    }
}

Describe 'Invoke-SpeechIn' {
    BeforeEach { $script:Wav = Join-Path ([System.IO.Path]::GetTempPath()) ('note-' + [guid]::NewGuid().ToString('N') + '.wav'); New-Wav $script:Wav }
    AfterEach { Remove-Item -LiteralPath $script:Wav -Force -ErrorAction SilentlyContinue }

    It 'returns the transcript from a loopback listener and does not echo the key' {
        $key = 'client-key-not-for-logs'
        $fake = Start-FakeSpeech 'ok' $key
        try {
            $r = Invoke-SpeechIn -AudioPath $script:Wav -Endpoint "http://127.0.0.1:$($fake.Port)/v1/audio/transcriptions" -ClientKey $key
            $r.Ok | Should -BeTrue
            $r.Text | Should -Be 'hello fleet'
            ($r | ConvertTo-Json -Compress) | Should -Not -Match 'client-key-not-for-logs'
        }
        finally { [void]$fake.Handle.AsyncWaitHandle.WaitOne(3000); $fake.PowerShell.Dispose(); Remove-Item $fake.Hits -Force -ErrorAction SilentlyContinue }
    }

    It 'does not copy a failing response body that contains the key' {
        $key = 'client-key-not-for-logs'
        $fake = Start-FakeSpeech 'echo-key' $key
        try {
            $r = Invoke-SpeechIn -AudioPath $script:Wav -Endpoint "http://127.0.0.1:$($fake.Port)/v1/audio/transcriptions" -ClientKey $key
            $r.Ok | Should -BeFalse
            $r.Code | Should -Be 'E_INTERNAL'
            $r.Message | Should -Not -Match 'client-key-not-for-logs'
        }
        finally { [void]$fake.Handle.AsyncWaitHandle.WaitOne(3000); $fake.PowerShell.Dispose(); Remove-Item $fake.Hits -Force -ErrorAction SilentlyContinue }
    }

    It 'does not follow a redirect' {
        $key = 'client-key-not-for-logs'
        $fake = Start-FakeSpeech 'redirect' $key
        try {
            $r = Invoke-SpeechIn -AudioPath $script:Wav -Endpoint "http://127.0.0.1:$($fake.Port)/v1/audio/transcriptions" -ClientKey $key
            $r.Ok | Should -BeFalse
            $r.Code | Should -Be 'E_FORBIDDEN'
            $r.Message | Should -Not -Match 'example.invalid'
            [int]([System.IO.File]::ReadAllText($fake.Hits)) | Should -Be 2
            (Get-Content -LiteralPath $fake.Log)[0] | Should -Be '/__fleethacker/id auth=0'
        }
        finally { [void]$fake.Handle.AsyncWaitHandle.WaitOne(4000); $fake.PowerShell.Dispose(); Remove-Item $fake.Hits, $fake.Log -Force -ErrorAction SilentlyContinue }
    }

    It 'does not send the key when the endpoint is not Fairlead' {
        $key = 'client-key-not-for-logs'
        $fake = Start-FakeSpeech 'ok' $key -Tool 'other'
        try {
            $r = Invoke-SpeechIn -AudioPath $script:Wav -Endpoint "http://127.0.0.1:$($fake.Port)/v1/audio/transcriptions" -ClientKey $key
            $r.Ok | Should -BeFalse
            $r.Code | Should -Be 'E_FORBIDDEN'
            $r.Message | Should -Be 'Speech endpoint is not Fairlead.'
            $r.Message | Should -Not -Match 'client-key-not-for-logs'
            $log = @(Get-Content -LiteralPath $fake.Log)
            $log.Count | Should -Be 1
            $log[0] | Should -Be '/__fleethacker/id auth=0'
        }
        finally { [void]$fake.Handle.AsyncWaitHandle.WaitOne(4000); $fake.PowerShell.Dispose(); Remove-Item $fake.Hits, $fake.Log -Force -ErrorAction SilentlyContinue }
    }

    It 'does not send the key when the reported pid is not the listener' {
        $key = 'client-key-not-for-logs'
        $fake = Start-FakeSpeech 'ok' $key -ReportedPid 99999
        try {
            $r = Invoke-SpeechIn -AudioPath $script:Wav -Endpoint "http://127.0.0.1:$($fake.Port)/v1/audio/transcriptions" -ClientKey $key
            $r.Ok | Should -BeFalse
            $r.Code | Should -Be 'E_FORBIDDEN'
            $r.Message | Should -Be 'Speech endpoint pid does not hold the port.'
            $log = @(Get-Content -LiteralPath $fake.Log)
            $log.Count | Should -Be 1
            $log[0] | Should -Be '/__fleethacker/id auth=0'
        }
        finally { [void]$fake.Handle.AsyncWaitHandle.WaitOne(4000); $fake.PowerShell.Dispose(); Remove-Item $fake.Hits, $fake.Log -Force -ErrorAction SilentlyContinue }
    }

    It 'does not send the key when the reported path is not the process' {
        $key = 'client-key-not-for-logs'
        $fake = Start-FakeSpeech 'ok' $key -ReportedPath '/tmp/not-the-fairlead-process'
        try {
            $r = Invoke-SpeechIn -AudioPath $script:Wav -Endpoint "http://127.0.0.1:$($fake.Port)/v1/audio/transcriptions" -ClientKey $key
            $r.Ok | Should -BeFalse
            $r.Code | Should -Be 'E_FORBIDDEN'
            $r.Message | Should -Be 'Speech endpoint path does not match the process.'
            $log = @(Get-Content -LiteralPath $fake.Log)
            $log.Count | Should -Be 1
            $log[0] | Should -Be '/__fleethacker/id auth=0'
        }
        finally { [void]$fake.Handle.AsyncWaitHandle.WaitOne(4000); $fake.PowerShell.Dispose(); Remove-Item $fake.Hits, $fake.Log -Force -ErrorAction SilentlyContinue }
    }

    It 'reaches the loopback listener when a proxy is configured' {
        $key = 'client-key-not-for-logs'
        $fake = Start-FakeSpeech 'ok' $key
        $old = $env:http_proxy
        $env:http_proxy = 'http://127.0.0.1:9'
        try {
            $r = Invoke-SpeechIn -AudioPath $script:Wav -Endpoint "http://127.0.0.1:$($fake.Port)/v1/audio/transcriptions" -ClientKey $key
            $r.Ok | Should -BeTrue
            $r.Text | Should -Be 'hello fleet'
        }
        finally {
            if ($null -eq $old) { Remove-Item Env:http_proxy -ErrorAction SilentlyContinue } else { $env:http_proxy = $old }
            [void]$fake.Handle.AsyncWaitHandle.WaitOne(4000); $fake.PowerShell.Dispose(); Remove-Item $fake.Hits, $fake.Log -Force -ErrorAction SilentlyContinue
        }
    }

    It 'refuses a non-loopback endpoint before any request' {
        $r = Invoke-SpeechIn -AudioPath $script:Wav -Endpoint 'http://example.invalid/v1/audio/transcriptions' -ClientKey 'k'
        $r.Ok | Should -BeFalse
        $r.Code | Should -Be 'E_FORBIDDEN'
    }
}

Describe 'Test-SpeechInFairleadDecision' {
    It 'refuses two loopback listeners and a non-loopback listener' {
        $two = @(
            [pscustomobject]@{ Address = '127.0.0.1'; Pid = 10; Loopback = $true },
            [pscustomobject]@{ Address = '127.0.0.1'; Pid = 11; Loopback = $true }
        )
        Test-SpeechInFairleadDecision -Tool 'fairlead' -ReportedPid 10 -ReportedPath '/opt/microsoft/powershell/7/pwsh' -Listeners $two | Should -Be 'listeners'
        $wide = @([pscustomobject]@{ Address = '0.0.0.0'; Pid = $PID; Loopback = $false })
        Test-SpeechInFairleadDecision -Tool 'fairlead' -ReportedPid $PID -ReportedPath (Get-Process -Id $PID).Path -Listeners $wide | Should -Be 'listeners'
        Test-SpeechInFairleadDecision -Tool 'fairlead' -ReportedPid $PID -ReportedPath (Get-Process -Id $PID).Path -Listeners @() | Should -Be 'listeners'
    }
}

Describe 'Get-SpeechInFallback' {
    It 'reports windows or none and does not throw' {
        $v = Get-SpeechInFallback
        $v | Should -BeIn @('windows', 'none')
    }
}
