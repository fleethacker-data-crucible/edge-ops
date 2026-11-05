# Suite conventions

These apply to every tool repository in `fleethacker-data-crucible` that is listed in `catalog.json`.

## Repository
- **License:** MIT (`LICENSE` at the root). Open-source code we use keeps its own notice: see [Attribution for open-source code](#attribution-for-open-source-code).
- **Description:** one sentence, filled in.
- **Topics:** `fleethacker-suite`, `powershell-5-1`, `no-admin`, `offline`, `app-whitelist-friendly`, plus one of `browser-only`, `browser-ui`, `data-ai`, `security`.
- **Main copy:** the org copy is canonical. Links point to `github.com/fleethacker-data-crucible/<repo>`.
- **README:** follows [templates/TOOL-README-TEMPLATE.md](templates/TOOL-README-TEMPLATE.md).
- **Version marker** at the root (`VERSION` semver, or `__version.info`), plus a `CHANGELOG.md`. See *Settings and versioning*.

## Attribution for open-source code
MIT covers our own code. Open-source code we copy, vendor, adapt or ship alongside a tool usually carries its own licence, and most licences (MIT, BSD, Apache-2.0, OFL and others) require that the copyright notice and licence text travel with it. Each repo records this in one place, so a reviewer can answer "what did we use, and what do we owe?" from the repo alone.
- **What counts:** anything not written for this repo that ends up in it or in its release zip: vendored JS or CSS (`ui\js\vendor\`), fonts, icons and images, copied or adapted code snippets, templates, and any bundled binary. It also covers code we used as the basis for a design or port, when its licence asks for credit. A dependency we only install or call at development time, and that is not shipped, needs no entry unless its licence says otherwise.
- **Where:** a `THIRD-PARTY-NOTICES.md` at the repo root. A repo with nothing to attribute may omit the file, and says so in its README *License* section ("No third-party code").
- **Per entry, record:** name and version, upstream URL, licence (SPDX id, for example `MIT`, `Apache-2.0`, `OFL-1.1`), copyright holder and year as the upstream states them, where it lives in this repo (path), what we changed (nothing, or a short note), and the full licence text or a link to the file that holds it.
- **Keep the licence file with the code:** vendored folders keep their upstream `LICENSE` or `OFL` file beside the code, as `ui-kit` does for its fonts (`OFL-Exo2.txt`, `OFL-SyneMono.txt`). Never strip a licence header from a copied file.
- **Compatibility:** only bring in code whose licence allows redistribution inside an MIT repo (MIT, BSD, Apache-2.0, ISC, OFL for fonts). Ask before adding GPL, AGPL, "non-commercial" or unlicensed code; no licence means all rights reserved.
- **Packaged zips:** the release zip includes `THIRD-PARTY-NOTICES.md` and the vendored licence files (see *Releases*).
- **Add the entry in the same PR** that adds the code, and update the README *License* section to link to the file.
- **Checklist for a tool repo:**
  - [ ] `LICENSE` is MIT with the right holder and year.
  - [ ] Every vendored, copied or adapted item is listed in `THIRD-PARTY-NOTICES.md` with the fields above.
  - [ ] Each vendored folder still contains its upstream licence file, and copied files keep their headers.
  - [ ] The README *License* section says "MIT" and links to `THIRD-PARTY-NOTICES.md` (or says "No third-party code").
  - [ ] The release zip contains the notices file and the licence files.

## Reference repos
The standard is modeled on the two most settled tools, **phoenix-lai** and **data-noodler**. When this file and those repos disagree, the repos win, unless the repo pattern breaks a hard constraint (PS 5.1, no admin, offline, loopback-only bind). Those exceptions are listed in [STANDARDS-EXCEPTIONS.md](STANDARDS-EXCEPTIONS.md).

## Folder layout
```
ToolName\
  ToolName.lnk          user launcher (see Launchers)
  README.md  LICENSE  CHANGELOG.md  version marker (VERSION or __version.info)
  src\ or server\        host scripts (.ps1) and C# sources (.cs); the entry script lives here, not in the root
  html\ or ui\           local HTML/CSS/JS, with third-party JS vendored under ui\js\vendor\ (no CDN)
  config\               shipped defaults (JSON)
  logs\  temp\          created at run time, git-ignored
  tests\                Pester 5 smoke tests (*.Tests.ps1)
  *.bat                 developer/utility only (Package.bat, Unpack.bat, *_Install.bat)
```

## Runtime compatibility
- Windows PowerShell **5.1** and .NET Framework 4.x only. Entry scripts fail fast on anything else:
  `if ($PSVersionTable.PSVersion.Major -ne 5) { throw "Run with Windows PowerShell 5.1 (powershell.exe)..." }` (phoenix-lai `src\run.ps1`).
- UI: HTML/CSS/vanilla JS in current Edge/Chrome. All assets are local. Vendor third-party JS into the repo (data-noodler `ui\js\vendor\billboard\`). No CDN.
- **Do not** require admin, installers, registry writes outside HKCU, services, scheduled tasks, or a third-party EXE/DLL.
- **C# is allowed and preferred for heavy logic**, compiled at run time with `Add-Type` against .NET Framework assemblies only (C# 5). Either compile it in memory (phoenix-lai `src\run.ps1`) or cache the DLL under `<root>\temp\` keyed by a source hash (data-noodler `server\engine-loader.ps1`). Flag `csharpRuntimeCompile` in the catalog; some app-control policies block it.
- Keep temp files inside the tool: `$env:TEMP = $env:TMP = <root>\temp\sys`.

## PowerShell 5.1 rules
Every `.ps1`/`.psm1` must run on stock **Windows PowerShell 5.1** (`powershell.exe`), not just `pwsh`.
- **No PS7-only syntax:** no ternary `a ? b : c`, no `??` / `??=`, no `?.` / `?[]`, no `&&` / `||` pipeline chains, no `ForEach-Object -Parallel`, no `-AsHashtable` on `ConvertFrom-Json`, no `Join-String`, `Get-Error` or other PS7-only cmdlets. (`[Type]::new()` is fine on 5.1.)
- **Encoding: ASCII only** in `.ps1`/`.psm1`/`.psd1`, because PS 5.1 reads BOM-less files as ANSI (data-noodler `engine-loader.ps1`). If a file must contain non-ASCII, save it as UTF-8 **with BOM**. Write output files with an explicit encoding (`[IO.File]::AppendAllText(path, text, [Text.Encoding]::UTF8)`).
- **Errors:** `$ErrorActionPreference = 'Stop'` at the top of every entry script. `Set-StrictMode` is optional; neither reference repo uses it.
- **No admin, installs or CDN** at run time. Dev and CI may install the tools with `-Scope CurrentUser`:
  `Install-Module Pester -MinimumVersion 5.5.0 -MaximumVersion 5.99.99 -Scope CurrentUser -Force -SkipPublisherCheck` and `Install-Module PSScriptAnalyzer -Scope CurrentUser -Force`.
- **Structure:** a thin PowerShell host plus dot-sourced helper scripts (`. (Join-Path $PSScriptRoot 'engine-loader.ps1')`) and C# sources. Modules (`.psm1`) are optional. If PowerShell classes inherit across files, dot-source them in dependency order from one loader. The CI parse step ignores the resulting standalone `TypeNotFound`. List any other files CI should skip in `.ci/lint-exclude.txt`.
- **Lint:** `Invoke-ScriptAnalyzer -Path . -Recurse -Settings .\PSScriptAnalyzerSettings.psd1` (copy the file from edge-ops). It enables `PSUseCompatibleSyntax` (5.1), `PSUseCompatibleCommands` (Windows 10/11 desktop 5.1 profile `win-48_x64_10.0.17763.0_5.1.17763.316...`, with `Clear-Host` ignored) and the legacy `PSUseCompatibleCmdlets` (`desktop-5.1.14393.206-windows`). Style rules the reference repos skip by design are excluded (empty catch, ShouldProcess, singular nouns, approved verbs). `PSUseCompatibleTypes` is off because types loaded with `Add-Type` are false positives.

## Launchers
- The user launcher is a **`ToolName.lnk`** in the tool root that runs
  `%SystemRoot%\System32\conhost.exe --headless %SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -STA -ExecutionPolicy Bypass ...`
  `conhost --headless` hides the console, so **no VBS is needed** (phoenix-lai `Phoenix_LAI_Server.lnk`, data-noodler `Data Noodler.lnk`).
- The shortcut must work from any extract folder. Use phoenix-lai's `-EncodedCommand` bootstrap, which finds the `.lnk` path and runs `src\<entry>.ps1` beside it. Generate it with [templates/launcher/New-ToolShortcut.ps1](templates/launcher/New-ToolShortcut.ps1). Icons come from `%SystemRoot%` or the tool folder, never a dev-machine path.
- One `.lnk` per program (phoenix-lai ships a server and a client: `Phoenix_LAI_Server.lnk`, `Phoenix_Client.lnk`).
- A `.bat` is for developer and utility tasks only (`Package.bat`, `Unpack.bat`, `*_Install.bat`): a visible console that runs `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0<script>.ps1" %*`, then `pause`. Template: [templates/launcher/ToolName-Dev.bat](templates/launcher/ToolName-Dev.bat). An existing `.bat` launcher may stay as a dev fallback.
- Keep `.bat` files CRLF through `.gitattributes` (`*.bat text eol=crlf`): [templates/gitattributes](templates/gitattributes).
- Common switches: `-Port <n>`, `-NoBrowser`, `-CheckOnly` (self-check, no server).

## Local servers
- **Bind rule:** HttpListener on `http://localhost:<port>/` (or TcpListener on `IPAddress.Loopback`), never `+` / `*` / `0.0.0.0`. `http://localhost:` needs no URL ACL or admin (keystone, data-noodler). **Enforced:** `Start-LoopbackListener` calls `Assert-LoopbackPrefix` before `Prefixes.Add`, which accepts only `localhost`, `127.0.0.1` or `[::1]` and throws on `+`, `*`, `0.0.0.0` or any other host. This matters because, when elevated, `http://+:` and `http://*:` really do listen on every interface.
- **Port blocks:** each tool owns one contiguous block in [PORTS.md](PORTS.md) and walks upward only inside it. Block full means a clear error. No random fallback and no port 0 fallback. Use `Resolve-FleetPort` from [tools/fleet-port/FleetPort.psm1](tools/fleet-port/FleetPort.psm1) (copy it into the tool if the tool can't import from the hub).
- **Self-detection:** serve `GET /__fleethacker/id` (`{tool, version, pid, path}`) and `POST /__fleethacker/shutdown` (`Invoke-FleetIdEndpoint`). Before skipping a busy port, probe it; if it is this tool, apply the tool's one declared policy: `reuse` (default for single-user UI tools), `restart`, `multi` or `exclusive` (tools holding a lease: GPU, Outlook). A **newer** running copy is always reused, never downgraded, and the launcher logs "stale launcher". The exception is `multi`, which always starts another copy on the next free port in its block. See [PORTS.md](PORTS.md#self-detection-and-policies).
- Check every request the way keystone's `Test-KeystoneWebRequest` does: `[Net.IPAddress]::IsLoopback($Request.RemoteEndPoint.Address)`, `Host` is `localhost:<port>` (or `127.0.0.1:<port>`), and `Origin`, when present, is the same origin.
- Free-port checks should test **both** IPv4 (`127.0.0.1`) and IPv6 (`::1`) loopback, because `localhost` can resolve to either (`Test-LoopbackPortFree` in the snippet).
- A tool may stop **its own** previous instance only through its policy: the shutdown endpoint first, then `Stop-Process` on the self-reported pid after checking that process's command line or path (a `.pid` file plus the same check is fine until the tool serves the id endpoint). Never stop or take over another program.
- Closing the window or exiting stops the server and removes the `.pid` file.
- Host skeleton: [templates/host/Start-ToolName.ps1](templates/host/Start-ToolName.ps1).

## CLI and API for agents
**Status: proposed, waiting on Jeremy's decision** ([Fleet CLI parity](https://github.com/fleethacker-data-crucible/fleethacker-comms-data-crucible/blob/main/proposals/cli-parity/README.md), discussion #69). Until it is adopted these are **SHOULD** for new work; once adopted they become **MUST**. The idea: if a person can click it, an agent can call it.
- **No GUI-only code paths.** A button handler only collects input and calls a command in the tool's core.
- **Every action is a named command,** `<tool> <noun> <verb>` (for example `capstan marker add`, `windlass playbook show`). The same name is used for the API route and the MCP tool.
- **Machine-readable output.** Every command supports `--json` with a stable, versioned schema (a `"schema": "<tool>.<thing>/<n>"` field). Exit code 0 is success; any other code is a named error. A command that writes a file takes `--out <file>` and writes UTF-8 **without a BOM**, because `>` in Windows PowerShell 5.1 writes UTF-16 LE.
- **Headless.** Nothing waits on a dialog: confirmations take `--yes`, risky actions support `--dry-run`.
- **Self-describing.** `<tool> commands --json` lists every command with its inputs and outputs; the API and MCP tool list come from the same registry.
- **Open project files.** Plain JSON with a published schema and a version number.
- **Stable IDs across the suite.** A clip, frame or asset keeps one ID from creation, shared between tools.
- **Locked to this user.** An HTTP API or MCP server binds loopback only (see Local servers), requires a per-session token written to `%LOCALAPPDATA%\<Tool>` (readable only by the signed-in user; 401 without it), checks `Host` and `Origin` on every request, sends no CORS headers, and refuses delete, overwrite or publish unless the call sets `confirm: true` (logged). The Researcher checks an API before it ships.
- **Parity test in CI.** Every GUI action is registered against its command; CI fails when one has no command or a command has no test.
- **Record it in the catalog.** Each tool's entry in [catalog.json](catalog.json) carries an optional `automation` block, shown as badges on the hub and a *For agents* table on the tool's page. Record only what is verified; leave it out rather than guess:

  ```json
  "automation": {"cli": true, "json": true, "api": "openai-v1", "mcp": false, "describe": "Launch-Tool.bat commands --json"}
  ```

  `cli`: every user action runs from the command line. `json`: commands take `--json`. `api`: `"openai-v1"` for an OpenAI-compatible `/v1`, another short name for a tool's own loopback API, or `null`. `mcp`: an MCP server. `describe`: the command that lists the tool's commands, or `null`.

## Voice (speech out and in)
**Status: accepted 2026-10-30 ([edge-ops issue 37](https://github.com/fleethacker-data-crucible/edge-ops/issues/37)). Speech out is documented in TalkForge; speech in is planned.** The exact request, reply and error format is TalkForge's [voice contract](https://github.com/fleethacker-data-crucible/TalkForge/blob/main/docs/VOICE-CONTRACT.md) (open as TalkForge PR 25, so the link works once it merges). This section is the rule for the apps that call it; it does not repeat the contract.
- **Speech out:** TalkForge is the suite voice. An app that speaks uses `POST /v1/audio/speech` (OpenAI-shaped), or `talkforge speak` from a script. Voices are local files, and nothing leaves the machine.
- **One address:** apps reach speech through Fairlead, `/v1/audio/speech` for speech out and `/v1/audio/transcriptions` for speech in, on `127.0.0.1:8776`. Configure it the way an app configures its model route: a base-URL setting that defaults to Fairlead, and the app's own Fairlead client key. Fairlead forwards speech out to TalkForge (`http://127.0.0.1:25009`, with TalkForge's token as that backend's key).
- **Calling TalkForge directly** (tests, or where Fairlead is not running): loopback only; `Authorization: Bearer <token>` on every request; call from a program, never from a web page (TalkForge refuses any request with an `Origin` header and any non-loopback `Host`).
- **Token:** read it from Lazarette by name at start ([credentials rule](https://github.com/fleethacker-data-crucible/edge-ops/issues/37)). Do not keep it in config files, the registry or the browser, and never log it.
- **Be patient and degrade quietly:** the first request for a voice loads it, and synthesis runs about 1 to 1.5 seconds per second of audio on a laptop CPU, so use client timeouts of a minute or more. On `503` (voice files missing), `401` or no connection, the app carries on without sound and shows text; it does not send the text to a network voice service.
- **Speech in:** starts from the Whisper assets PacketRat carries; Windows speech recognition is the fallback. The shared speech-in module is **planned**: it will be hosted next to the UI kit and vendored like FleetPort. Until it exists, an app that needs speech in documents what it uses.
- **Changing the contract:** change TalkForge's voice contract first, in the same pull request as the code, and update this section only if the rule for callers changes.

## Logging
- Logs go in `logs\` inside the tool (`<root>\logs\` or `server\logs\`), one timestamped file per run: `ToolName_yyyy_MM_dd_HHmmss.log` (data-noodler). A machine-readable `.jsonl` next to it is optional (phoenix-lai `ChatLog.cs`).
- Line format: `yyyy-MM-dd HH:mm:ss  [LEVEL] text`.
- The console is hidden, so a fatal start-up error goes to the log **and** a WinForms message box (`Show-Fatal` plus `trap`, data-noodler `server\server.ps1`).
- Logs, `temp\`, `.pid` and `settings.json` holding user state are git-ignored ([templates/gitignore](templates/gitignore)).

## Settings and versioning
- User settings: `settings.json` beside the host script (port, browser, theme). Shipped defaults go in `config\`.
- A version marker in the root (`VERSION` with semver, or a `__version.info` build stamp as in phoenix-lai) plus `CHANGELOG.md`.
- Packaging scripts (`Package.ps1` + `Package.bat`) are fine. Release zips come from the release workflow.

## Tests
- A self-check mode in the entry script (`-CheckOnly`, phoenix-lai `src\run.ps1`): static locality and safety checks with no server.
- Pester 5 smoke tests in `tests\*.Tests.ps1` (start from [templates/tests/](templates/tests/)): every `.ps1` parses on 5.1, the server binds loopback only (fails only on `+`, `*`, `0.0.0.0` or a non-loopback address; `localhost` is fine).
- Browser, desktop, Outlook and GPU tests on the shared VM follow [Test isolation](#test-isolation-shared-windows-test-vm).
- CI: [templates/workflows/ci.yml](templates/workflows/ci.yml) on windows-latest with `shell: powershell` (5.1). It triggers on `main` and `master`. The tests path is `TESTS_PATH`, default `tests`, falling back to `templates/tests`; finding 0 tests is a warning. The token can't write `.github/workflows`, so the file is staged under `templates/`.

## Test isolation (shared Windows test VM)
Source: [tools/test-harness/](tools/test-harness/) (Zombie Admin's harness). Chrome debug ports 9300-9399 are reserved in [PORTS.md](PORTS.md).

Several bots and CI runners share the Windows test VM. These rules keep their browser and UI tests from interfering with each other.

### Setup
- Module: `tools/test-harness/FleetTestHarness.psm1` (Windows PowerShell 5.1+). `Import-Module .\FleetTestHarness.psm1`
- One-time elevated setup: `Install-FleetLockRoot.ps1` creates `C:\ProgramData\fleethacker\locks` and grants Users Modify.
- Override the lock folder with `$env:FLEET_LOCK_ROOT` (the tests do this).

### Browser tests: always use isolated Chrome
```powershell
$c = Start-IsolatedChrome -Agent uikit -RunId $env:GITHUB_RUN_ID -Headless -Url 'file:///D:/x/demo.html'
try { # drive via CDP at http://127.0.0.1:$($c.Port) ($c.DevToolsUrl)
} finally { Stop-IsolatedChrome $c | Out-Null }
```
- Profile: `%LOCALAPPDATA%\fleethacker\chrome\<agent>-<runid>`, always fresh and deleted on stop.
- Debug port: picked at random from **9300-9399**, checked free (Get-NetTCPConnection plus a TcpListener probe), and leased as `port-<n>` while Chrome starts.
- Never use the user's default profile or a fixed debug port. Never `Stop-Process chrome`. Stop only kills processes whose command line contains your profile path.

### Leases for resources that can't be shared
| Resource | Use for |
|---|---|
| `desktop-focus` | anything that needs the interactive desktop or foreground: screenshots, SendKeys/UI Automation, markup tests (lasso), High Contrast or theme toggles |
| `outlook-com` | Outlook COM automation (mailhawk) |
| `gpu` | GPU-heavy work (phoenix-lai) |
| `port-<n>` | a fixed tool port when port fallback is disabled |

```powershell
$l = Enter-FleetLock desktop-focus -Owner "uikit/$env:GITHUB_RUN_ID" -TimeoutSec 600 -Heartbeat
try { ... } finally { Exit-FleetLock $l | Out-Null }
```
- Aliases: `Acquire-FleetLock`, `Renew-FleetLock`, `Release-FleetLock`.
- File `<resource>.json`: owner, pid, host, acquired, heartbeat (ISO 8601 UTC), token.
- Creation is atomic (`FileMode.CreateNew`). Stale means the heartbeat is older than 5 min or the owner PID is dead on this host. Takeover is serialized by a `<resource>.takeover` guard and a rename to a tombstone, so only one taker wins.
- Holding for more than ~4 min: pass `-Heartbeat` (renews every 30 s while the owner PID lives) or call `Update-FleetLock` yourself.
- `Exit-FleetLock` verifies the token and won't release someone else's lock.
- Status: `Get-FleetLocks | Format-Table` (has an IsStale column).
- **Lock-root permissions:** Users:Modify on the lock folder lets *any* local user delete or overwrite other users' lock files. That's acceptable because this is a cooperative lock between our own runners, not a security boundary. Don't rely on it to keep out a hostile process.
- **Test isolation caveat:** the harness's own Pester tests set `FLEET_LOCK_ROOT` to a temp folder but still launch Chrome on the real 9300-9399 ports. Their `port-<n>` leases are invisible to other jobs, so a concurrent job may pick the same port; the free-port probe is the only guard. Avoid running the harness tests alongside other browser jobs on the shared VM.

### Rules
1. Always lease `desktop-focus` for screenshot, SendKeys, focus, or display-setting tests.
2. Always use isolated Chrome for browser tests.
3. Always release and stop in `finally`.
4. Keep leases short; acquire just before the critical section.
5. Don't delete lock files by hand; let stale takeover handle crashed owners.

> **No-admin caveat:** `Install-FleetLockRoot.ps1` is a one-time setup script that writes to `C:\ProgramData` and changes an ACL. It is test-VM infrastructure, not tool runtime. Without elevation, set `$env:FLEET_LOCK_ROOT` to a per-user folder such as `$env:LOCALAPPDATA\fleethacker\locks` (which only coordinates runners under the same Windows account).

## Releases
- Tag `vX.Y.Z` → the reusable workflow `edge-ops/.github/workflows/release-zip.yml` builds:
  - `ToolName-vX.Y.Z.zip`: a single top-level folder `ToolName-vX.Y.Z/` containing the tool and `VERSION`
  - `ToolName-vX.Y.Z.zip.sha256`
- Big binaries (models, packages) go in release assets, **never** in git history.
- The hub links to `releases/latest`.

## Branch pruning
- **Rule (Jeremy, Oct 26 2026):** kill after merge, but only if the branch has no commits after its merge. Delete a branch **only** if it's the head of a merged same-repo PR into the default branch **and** its current tip is exactly that PR's merged head SHA. Keep any branch with commits after its merge.
- **No other deletes:** no stale, age-based, no-PR or "already on the default branch" deletes.
- **Never deleted:** the default branch, `main`, `master`, `hub/**`, `preview/**`, `release/**`; protected branches; any branch that is the head (same repo) or **base** of an open PR. Deleting a base closes its PRs.
- Template: `templates/workflows/prune-merged-branches.yml`. It's the **one canonical copy**, the same bytes as the shared file in every repo.
- **Adopt it:** copy the file unchanged to `.github/workflows/prune-merged-branches.yml` in the tool repo.
  - Pushing that path needs a token with `workflow` scope (Zombie Admin pushes).
  - After the merge, run it once by hand (`dry_run` is on by default) and read the PLAN lines.
- **Keep every copy identical:** never edit it per repo. Change the template here, then roll the same bytes out to every repo.
- **Runs on** `[self-hosted, Windows, X64]` in Windows PowerShell 5.1 (`shell: powershell`). Windows runners require `shell: powershell` for every run step ([CI shells](https://github.com/fleethacker-data-crucible/fleethacker-comms-data-crucible/blob/main/STANDARDS.md#ci-shells)), so the file is PS 5.1 rather than Python or JavaScript.
- **Triggers:** every push to `main` (deletes for real) and `workflow_dispatch` with a `dry_run` input (**default on**: a manual run only logs `PLAN delete` and `DRY RUN would delete` lines; uncheck it to delete).
- **Re-check before delete:** right before each delete the run re-reads the branch tip. If it no longer equals the merged head SHA, the branch is kept (`SKIP tip moved since the merge`). A branch that's already gone is skipped. A PR whose fork was deleted (null head repo) never matches.
- **Token:** `GITHUB_TOKEN` only, with `contents: write` and `pull-requests: read`.
- **Errors:** an API error stops the run; the remaining branches wait for the next run.

## Regenerate the catalog fallback (PowerShell 5.1)
`scripts/Build-Site.ps1` rewrites `assets/catalog-data.js` from `catalog.json` (no BOM) and copies that same file into `_site/`. Run:
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-Site.ps1
```
