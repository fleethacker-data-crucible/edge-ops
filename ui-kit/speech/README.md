# Speech in (v0.1.0)

Shared client for speech in. Copy `SpeechIn.psm1` into an app the way the app copies `tools/fleet-port/FleetPort.psm1`. Windows PowerShell 5.1, no admin, no install.

The call goes to Fairlead, `POST /v1/audio/transcriptions` on `http://127.0.0.1:8776` (or `localhost` on another loopback port). Any other URL is refused. Redirects are not followed. The client key is an argument to `Invoke-SpeechIn`; the module does not store it, log it, or put it in an error message.

Whisper weights are not in this folder. PacketRat's release carries those assets, and Fairlead serves the transcription. `Get-SpeechInFallback` reports `windows` when the `System.Speech` assembly loads and `none` otherwise. It does not start a recognizer. When the call cannot run, the app keeps showing text.

```powershell
Import-Module .\SpeechIn.psm1
$r = Invoke-SpeechIn -AudioPath .\note.wav -ClientKey $key
```
