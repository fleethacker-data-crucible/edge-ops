# Suite conventions

These apply to every tool repository in `fleethacker-data-crucible` that is listed in `catalog.json`.

## Repository
- **License:** MIT (`LICENSE` at the root).
- **Description:** one sentence, filled in.
- **Topics:** `fleethacker-suite`, `powershell-5-1`, `no-admin`, `offline`, `app-whitelist-friendly`, plus one of `browser-only`, `browser-ui`, `data-ai`, `security`.
- **Main copy:** the org copy is canonical. Links point to `github.com/fleethacker-data-crucible/<repo>`.
- **README:** follows [templates/TOOL-README-TEMPLATE.md](templates/TOOL-README-TEMPLATE.md).
- **Version marker** at the root (`VERSION` semver, or `__version.info`), plus a `CHANGELOG.md`. See *Settings and versioning*.

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
- **Bind rule:** HttpListener on `http://localhost:<port>/` (or TcpListener on `IPAddress.Loopback`), never `+` / `*` / `0.0.0.0`. `http://localhost:` needs no URL ACL or admin (keystone, data-noodler).
- Pick the port as described in [PORTS.md](PORTS.md#port-handling-standard): preferred port, then the tool's range. Snippet: [templates/ports/LoopbackPort.ps1](templates/ports/LoopbackPort.ps1).
- Check every request the way keystone's `Test-KeystoneWebRequest` does: `[Net.IPAddress]::IsLoopback($Request.RemoteEndPoint.Address)`, `Host` is `localhost:<port>` (or `127.0.0.1:<port>`), and `Origin`, when present, is the same origin.
- Free-port checks should test **both** IPv4 (`127.0.0.1`) and IPv6 (`::1`) loopback, because `localhost` can resolve to either (`Test-LoopbackPortFree` in the snippet).
- A tool may stop **its own** previous instance through a `.pid` file, after checking that process's command line (data-noodler). Never stop or take over another program.
- Closing the window or exiting stops the server and removes the `.pid` file.
- Host skeleton: [templates/host/Start-ToolName.ps1](templates/host/Start-ToolName.ps1).

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
- CI: [templates/workflows/ci.yml](templates/workflows/ci.yml) on windows-latest with `shell: powershell` (5.1). It triggers on `main` and `master`. The tests path is `TESTS_PATH`, default `tests`, falling back to `templates/tests`; finding 0 tests is a warning. The token can't write `.github/workflows`, so the file is staged under `templates/`.

## Releases
- Tag `vX.Y.Z` → the reusable workflow `edge-ops/.github/workflows/release-zip.yml` builds:
  - `ToolName-vX.Y.Z.zip`: a single top-level folder `ToolName-vX.Y.Z/` containing the tool and `VERSION`
  - `ToolName-vX.Y.Z.zip.sha256`
- Big binaries (models, packages) go in release assets, **never** in git history.
- The hub links to `releases/latest`.

## Regenerate the catalog fallback (PowerShell 5.1)
```powershell
$json = Get-Content .\catalog.json -Raw
Set-Content .\assets\catalog-data.js ("window.EDGE_OPS_CATALOG = " + $json + ";") -Encoding UTF8
```
