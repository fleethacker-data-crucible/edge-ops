# Port registry

Default loopback ports, taken from each tool's README and launch scripts. Every server tool should **fall back to a free port** if its default is busy. Pick new ports from the unused range below and add them here.

| Port | Tool | Override | Source |
|---|---|---|---|
| 1234 | Phoenix LAI server (OpenAI-compatible `/v1`) | see repo docs | phoenix-lai README |
| 8079 | Data Noodler (server control panel) | see repo docs | data-noodler README |
| 8765 | SnapShackle | `Launch-SnapShackle.bat -Port 9000` | `Start-SnapShackle.ps1` (auto-selects a free port) |
| 8765 | Shellback | `Launch-Shellback.bat -Port <n>` | `tools/Start-Shellback.ps1` (falls back to a free port) |
| 8766 | PacketRat | `Launch-PacketRat.bat -Port <n>` | `Start-PacketRat-Web.ps1` (falls back to a free port) |
| 8769 | Gangplank | `Launch-Gangplank.bat -NoBrowser 8770` | Gangplank README |
| 25000 | TalkForge static server | next free port automatically | talkforge README |
| — | ARC | n/a (CLI/WPF) | |

**Suggested range for new tools:** 8770–8799. Gangplank documents 8770 as its alternate port, so start new tools at 8771.
