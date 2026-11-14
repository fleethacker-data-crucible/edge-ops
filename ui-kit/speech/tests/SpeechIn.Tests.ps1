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

    function Start-FakeSpeech([string]$Mode, [string]$Key) {
        $tcp = New-Object System.Net.Sockets.TcpListener ([System.Net.IPAddress]::Loopback, 0)
        $tcp.Start()
        $port = ([System.Net.IPEndPoint]$tcp.LocalEndpoint).Port
        $tcp.Stop()
        $hits = Join-Path ([System.IO.Path]::GetTempPath()) ('speechhits-' + [guid]::NewGuid().ToString('N'))
        [System.IO.File]::WriteAllText($hits, '0')
        $ps = [PowerShell]::Create()
        [void]$ps.AddScript({
            param($Port, $Mode, $Key, $Hits)
            $l = New-Object System.Net.HttpListener
            $l.Prefixes.Add("http://127.0.0.1:$Port/")
            $l.Start()
            try {
                $ctx = $l.GetContext()
                $n = 0
                if (Test-Path -LiteralPath $Hits) { $n = [int]([System.IO.File]::ReadAllText($Hits)) }
                [System.IO.File]::WriteAllText($Hits, ([string]($n + 1)))
                $auth = [string]$ctx.Request.Headers['Authorization']
                $buf = New-Object byte[] 8192
                $read = 0
                $stream = $ctx.Request.InputStream
                while ($read -lt $buf.Length) {
                    $k = $stream.Read($buf, $read, $buf.Length - $read)
                    if ($k -le 0) { break }
                    $read += $k
                }
                $res = $ctx.Response
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
            finally { $l.Close() }
        }).AddArgument($port).AddArgument($Mode).AddArgument($Key).AddArgument($hits)
        $handle = $ps.BeginInvoke()
        Start-Sleep -Milliseconds 300
        [pscustomobject]@{ Port = $port; Handle = $handle; PowerShell = $ps; Hits = $hits }
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
            [int]([System.IO.File]::ReadAllText($fake.Hits)) | Should -Be 1
        }
        finally { [void]$fake.Handle.AsyncWaitHandle.WaitOne(3000); $fake.PowerShell.Dispose(); Remove-Item $fake.Hits -Force -ErrorAction SilentlyContinue }
    }

    It 'refuses a non-loopback endpoint before any request' {
        $r = Invoke-SpeechIn -AudioPath $script:Wav -Endpoint 'http://example.invalid/v1/audio/transcriptions' -ClientKey 'k'
        $r.Ok | Should -BeFalse
        $r.Code | Should -Be 'E_FORBIDDEN'
    }
}

Describe 'Get-SpeechInFallback' {
    It 'reports windows or none and does not throw' {
        $v = Get-SpeechInFallback
        $v | Should -BeIn @('windows', 'none')
    }
}
