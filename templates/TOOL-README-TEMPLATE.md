# ToolName

> One-sentence description of what the tool does.

![PS 5.1](https://img.shields.io/badge/PowerShell-5.1-5391FE) ![Chrome engine](https://img.shields.io/badge/browser-Chrome%2FEdge-4285F4) ![No admin](https://img.shields.io/badge/admin-not%20required-3a7d44) ![License MIT](https://img.shields.io/badge/license-MIT-blue)

Part of the [FleetHacker Edge-Ops suite](https://github.com/fleethacker-data-crucible/edge-ops).

**Status:** prototype | beta | preview | stable. Get local authorization and a security review before using it with sensitive data.

## Run (whitelisted Windows)
1. Download `ToolName-vX.Y.Z.zip` from [Releases → latest](../../releases/latest), verify the `.sha256`, then **Unblock** and extract the whole folder.
2. Double-click **`ToolName.bat`**.
3. The browser opens at `http://127.0.0.1:<port>/`. Close the console to stop.

Options: `ToolName.bat -Port <n>`, `-NoBrowser`, `-Demo`

## Requirements
| Needs | Yes/No |
|---|---|
| Windows PowerShell 5.1 | |
| Chrome/Edge | |
| Admin rights | No |
| Installs / third-party runtimes | No |
| Network access | |
| Runtime C# compile (Add-Type) | |
| GPU / Outlook / other | |
| Default port | see [PORTS.md](https://github.com/fleethacker-data-crucible/edge-ops/blob/main/PORTS.md) |

## What it does
Features, screenshots.

## How it works
Architecture, data locations (for example `%LOCALAPPDATA%\ToolName`), what leaves the machine (ideally nothing).

## Development and tests
How to run tests with `powershell.exe` 5.1.

## Security notes
Threat model and known limits.

## License
MIT. Third-party code and its notices: see [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) (or write "No third-party code").
