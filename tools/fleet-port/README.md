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

HttpListener ports are owned by PID 4 (System), so `Stop-FleetInstance` cannot prove ownership with `Get-NetTCPConnection`. Instead it reads `netsh http show servicestate view=requestq`. That query is read-only and **works for a standard (non-admin) user**: Zombie Admin's capture on Windows PowerShell 5.1, as a standard user on en-US Windows, exited 0 with the full English layout (`tests/netsh/requestq-en-real-8845.txt`).

When an older copy ignores `POST /__fleethacker/shutdown`, a well-formed older copy **is force-stopped** when all four proof conditions pass:

1. Graceful shutdown was tried first and the grace period ran out.
2. The reported path is an exact, absolute `-File` or executable match.
3. `netsh http show servicestate view=requestq` shows exactly one request queue with a URL on the port. Every URL it has on that port is plain `http` on a loopback host with the path `/`, and its only process is the self-reported pid. Loopback means `localhost`, `127.0.0.1` or `[::1]`. The IP-bound form `HTTP://127.0.0.1:<port>:127.0.0.1/` (host:port:ip, which TalkForge registers) is parsed explicitly and counts as loopback only when the bound ip is `127.0.0.1` or `::1`.
4. `/__fleethacker/id` re-checked on the port still reports the same tool and pid.

Only when the proof is **uncertain** does the launcher refuse, kill nothing, and stop with:

    An older <Tool> v<X> is still running; close its window and relaunch.

Uncertain means any of these: the queue also registers an extra prefix on the port (for example `http://localhost:<port>/legacy/`), a `+`, `*` or non-loopback host or bound ip, a URL line that can't be parsed, more than one queue on the port, an empty queue or more than one process, a queue pid that isn't the self-reported pid, a failed id re-check, or netsh output that isn't the English layout (another language, error text, non-zero exit).

The fixtures in `tests/netsh/` are the real capture plus one-edit variants of it; [tests/netsh/README.md](tests/netsh/README.md) lists each edit.

Tests: `Invoke-Pester tools/fleet-port/tests` (Pester 5; uses scratch ports 8834-8859).
