# Tray icons (v1.0.0)

Crisp, bold notification-area icons for every FleetHacker tool, drawn at the exact size Windows shows them.

## Why tool icons looked small and blurry next to enterprise apps
- **Detail too fine for 16 px.** A dark badge with a thin ring and a small emblem leaves about 6 px of symbol in a 16 px tray slot, dark on a dark taskbar. Enterprise tray icons are one bold shape that fills the square.
- **Wrong size, then shrunk.** `New-Object System.Drawing.Icon($path)` with no size picks the 32 px image, and Windows shrinks it to 16 px. Icons drawn on a 32 px bitmap are shrunk the same way.
- **`Bitmap.GetHicon` loses soft edges,** so shrunk art also gets jagged.
- **Display scale.** At 125 % or 150 % the tray wants 20 or 24 px. A process that is not DPI aware is told 16 px whatever the scale, so the icon is stretched.

## What this does
Each tool gets a rounded tile in its brand colour with one bold letter (L, W, F, C, S, P...). The tile's colour is nudged toward lighter or darker, keeping its hue, so it stands out from both a light and a dark taskbar, and the letter is black or white, whichever contrasts more. The art is drawn at the tray's size for this display, read from `AppliedDPI` so it is right even in a process that is not DPI aware. It is turned into an icon as in-memory `.ico` data with a real alpha channel. An optional corner badge shows state (`good`, `busy`, `bad`, `idle`), and plain status dots are available for monitors.

## Files
| File | Purpose |
|---|---|
| `FleetTrayArt.cs` | The drawing, as C# 5 with no P/Invoke, no network and no `GetHicon`. Compiles under Windows PowerShell 5.1 `Add-Type`, .NET Framework `csc` and .NET 8+, and passes phoenix-lai's source guard. |
| `FleetTray.ps1` | PowerShell loader: `Get-FleetTrayIcon`, `Get-FleetTrayDot`, `Get-FleetTraySize`, `Export-FleetTrayIco`, `Save-FleetTrayPreview`. If `Add-Type` is blocked it falls back to the tool's own `.ico`, at the right size. |
| `tests/FleetTray.Tests.ps1` | Pester 5: sizes per scale, alpha kept, badges, dots, the fallback, contrast for every tool, and the source rules. |

## Using it
PowerShell tools: copy `FleetTrayArt.cs` and `FleetTray.ps1` into the tool (for example `vendor/fleet-tray/`), dot-source `FleetTray.ps1`, then:

```powershell
$notifyIcon.Icon = Get-FleetTrayIcon -App lazarette -FallbackPath (Join-Path $root 'assets/brand/tray.ico')
$notifyIcon.Icon = Get-FleetTrayIcon -App capstan -Status bad
$notifyIcon.Icon = Get-FleetTrayDot -Status busy
```

On a background runspace thread, the type is already loaded process-wide: call `[FleetTray.Art]::ForApp('lazarette', '')` directly.

C# tools: add `FleetTrayArt.cs` to the sources and call `FleetTray.Art.ForApp("phoenix", null)` or `FleetTray.Art.Dot(FleetTray.Art.Busy)`.

Refresh a tool's fallback file with `Export-FleetTrayIco -App windlass -Path assets/brand/tray.ico`, and review the art with `Save-FleetTrayPreview -Path preview.png`.

To add a tool, add its letter and colour to `Apps` in `FleetTrayArt.cs`.
