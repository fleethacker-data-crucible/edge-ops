# Speech in (v0.1.0)

Shared client for speech in. Copy `SpeechIn.psm1` into an app the way the app copies `tools/fleet-port/FleetPort.psm1`. Windows PowerShell 5.1, no admin, no install.

The call goes to Fairlead, `POST /v1/audio/transcriptions` on `http://127.0.0.1:8776` (a `localhost` URL is pinned to `127.0.0.1`). Any other URL is refused. Before the client key is sent, `GET /__fleethacker/id` on that origin must report `tool` `fairlead`, exactly one loopback listener whose pid matches, and a path that is that process. On Windows the listener list comes from `netstat.exe` in `[Environment]::SystemDirectory` and the process comes from `Win32_Process`. `/proc` is read only when `$IsLinux` is true, which Windows PowerShell 5.1 does not define. An empty id path is refused. Otherwise the call returns `E_FORBIDDEN` and the key is not sent. The id probe and the request that carries the key do not use a proxy. Redirects are not followed. The client key is an argument to `Invoke-SpeechIn`; the module does not store it, log it, or put it in an error message.

Whisper weights are not in this folder. PacketRat's release carries those assets, and Fairlead serves the transcription. `Get-SpeechInFallback` reports `windows` when the `System.Speech` assembly loads and `none` otherwise. It does not start a recognizer. When the call cannot run, the app keeps showing text.

```powershell
Import-Module .\SpeechIn.psm1
$r = Invoke-SpeechIn -AudioPath .\note.wav -ClientKey $key
```
