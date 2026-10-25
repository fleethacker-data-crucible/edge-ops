# Port registry

Default loopback ports, taken from each tool's README and launch scripts. Every server tool should **fall back to a free port** if its default is busy. Pick new ports from the unused range below and add them here.

| Port | Tool | Override | Source |
|---|---|---|---|
| 1234 | Phoenix LAI server (OpenAI-compatible `/v1`) | see repo docs | phoenix-lai README |
| 8079 | Data Noodler (server control panel) | see repo docs | data-noodler README |
| 8765 | SnipHero Studio | `SnipHero.bat -Port 9000` | sniphero README (auto-selects a free port) |
| 8766 | MailHawk | `MailHawk.bat -Port <n>` | `Start-MailHawk-Web.ps1` (falls back to a free port) |
| 8769 | Keystone | `Launch-Keystone.bat -NoBrowser 8770` | keystone README |
| 25000 | TalkForge static server | next free port automatically | talkforge README |
| — | Synapse | n/a (runs from `file://`) | |
| — | ARC | n/a (CLI/WPF) | |

**Suggested range for new tools:** 8770–8799. Keystone documents 8770 as its alternate port, so start new tools at 8771.

## Port handling standard

Reference implementation: sniphero `modules/LocalHttp.ps1` (`SnipHero.Transport.Server`) and `Start-SnipHero.ps1`. The no-`Add-Type` version is [templates/ports/LoopbackPort.ps1](templates/ports/LoopbackPort.ps1).

1. **Loopback only.** Bind a `System.Net.Sockets.TcpListener` to `[IPAddress]::Loopback` (127.0.0.1). Never `+`, `*`, `0.0.0.0` or `localhost` prefixes. `HttpListener` on `http://localhost:<port>/` can need a URL ACL (admin), so avoid it for new tools.
2. **Preferred port first.** Take `-Port <n>` (default from the table above; new tools start at **8771**).
3. **Fall back.** If the bind fails with `AddressAlreadyInUse`, `AccessDenied` or `AddressNotAvailable`, try the next port (up to 20 by default). If none is free, bind to port `0` and let the OS pick one. Any other socket error is rethrown.
4. **No race.** Keep the bound listener and serve on it. Don't probe a port, close it and rebind.
5. **Tell the user.** Print `Port <n> is busy; using free loopback port <m>.` and open or print the **actual** URL `http://127.0.0.1:<m>/`.
6. **Never** stop, kill or take over another process holding the port.
7. **Validate requests.** Reject requests whose Host is not `127.0.0.1:<actual port>` (DNS-rebinding guard, as in sniphero).
8. **Test it.** [templates/tests/LoopbackPort.Tests.ps1](templates/tests/LoopbackPort.Tests.ps1) checks the 127.0.0.1 bind and the fallback.

Known gap: keystone binds `http://localhost:8769/` with HttpListener. It should move to this pattern in its lint/CI PR.
