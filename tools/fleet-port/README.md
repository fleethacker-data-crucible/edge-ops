# FleetPort

Port blocks with self-detection for FleetHacker tools (Windows PowerShell 5.1). Rules: [PORTS.md](../../PORTS.md#self-detection-and-policies).

```powershell
Import-Module "$PSScriptRoot\FleetPort.psm1"
$r = Resolve-FleetPort -Tool 'lasso' -Version $version          # walks 8765-8766 and applies 'reuse'
if ($r.Action -eq 'Reuse') { Start-Process $r.Url; exit 0 }      # same version already running
$listener = $r.Listener                                          # started on http://localhost:<port>/
while ($listener.IsListening) {
    $ctx = $listener.GetContext()
    $h = Invoke-FleetIdEndpoint -Context $ctx -Tool 'lasso' -Version $version -Path $PSCommandPath
    if ($h -eq 'shutdown') { break }                             # release leases, remove .pid, exit
    if ($h) { continue }
    # ... the tool's own routes ...
}
```

## Stopping an older copy on an http.sys port

HttpListener ports are owned by PID 4 (System), so `Stop-FleetInstance` cannot prove ownership with `Get-NetTCPConnection`. When an older copy ignores `POST /__fleethacker/shutdown`, the launcher stops with:

    An older <Tool> v<X> is still running; close its window and relaunch.

Nothing is killed, unless the full proof below passes:

1. Graceful shutdown was tried first.
2. The reported path is an exact, absolute `-File` or executable match.
3. `netsh http show servicestate view=requestq` shows exactly one request queue on the port. Its only URL there is `http://localhost:<port>/`, and its only process is the self-reported pid.
4. `/__fleethacker/id` re-checked on the port still reports the same tool and pid.

`Get-FleetHttpSysQueuePid` understands only the English netsh layout. It returns `$null`, which means refuse, for anything else: another language, error or access-denied text, an empty queue, more than one queue or process, or a `+`, `*` or IP host. The canned samples in `tests/netsh/` were written by hand in the documented English layout. They are not captures from a real machine.

Tests: `Invoke-Pester tools/fleet-port/tests` (Pester 5; uses scratch ports 8834-8859).
