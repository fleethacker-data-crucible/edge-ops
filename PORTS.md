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
