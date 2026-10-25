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

Tests: `Invoke-Pester tools/fleet-port/tests` (Pester 5; uses scratch ports 8835-8859).
