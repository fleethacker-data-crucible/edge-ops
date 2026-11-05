# Utility emblems

One small SVG per tool in `catalog.json`, named `<id>.svg`, shown on the hub cards by `assets/app.js`
(decorative: `alt=""` and `aria-hidden="true"`, because the card title names the tool). Local files only: no CDN, no binaries.

Style (shared by every Fleet mark): 64x64 viewBox, navy disc `#0d2233` with a 3px brass ring `#c9a66b`,
cream `#f1e4c8` and brass details, one accent colour per tool. The navy disc gives the edge on light themes
(14.6:1 on `#f4f3ef`) and the brass ring on dark themes (6.2:1 on `#2a2a2a`), so both themes clear 3:1 non-text contrast.

| File | Origin |
|---|---|
| halyard.svg | existing: Halyard `assets/brand/mark.svg` |
| lazarette.svg | existing: Lazarette `assets/brand/mark.svg` |
| gangplank.svg | existing: Gangplank `web/logo.svg` (same as `assets/brand/mark.svg`) |
| packetrat.svg | existing: PacketRat `assets/brand/mark.svg` |
| shellback.svg | existing: Shellback `assets/brand/mark.svg` |
| snapshackle.svg | existing: SnapShackle `assets/brand/mark.svg` |
| bowerbird.svg | existing: Bowerbird `assets/brand/mark.svg` |
| eight-bells.svg | existing: Eight-Bells `assets/brand/mark.svg` |
| capstan.svg | existing: Capstan `assets/brand/mark.svg` |
| scrimshaw.svg | existing: Scrimshaw `assets/brand/mark.svg` |
| semaphore.svg | existing: Semaphore `assets/brand/mark.svg` |
| fairlead.svg | existing: Fairlead `assets/brand/mark.svg` |
| halyard-ballast.svg | new, original SVG in the Fleet mark style |
| windlass.svg | new, original SVG in the Fleet mark style |
| talkforge.svg | new, original SVG in the Fleet mark style |
| data-noodler.svg | new, original SVG in the Fleet mark style |
| phoenix-lai.svg | new, original SVG in the Fleet mark style (upstream has PNG logos only) |
| bridge-warden.svg | new, original SVG in the Fleet mark style (a shield around a helm) |
| scope.svg | the SCOPE skin's mark (`assets/brand-scope.js`), not a tool: a periscope at the waterline, same style |

If a tool repo changes its mark, copy the new `mark.svg` here.

## Painted emblems (`painted/`)

`painted/<id>.png` (and `<id>-light.png` where the tool ships a light variant) is the tool's full painted emblem from its
repo's `assets/brand/` (`emblem-dark-transparent.png`, else `emblem-dark.png` with the flat navy field knocked out, else
`emblem-transparent.png`; Phoenix LAI from `html/assets/brand/emblem-transparent.png` and `fleet-emblem-light.png`), trimmed and fitted into 256x256 with an
8 px margin. Only the SCOPE skin shows them, beside the card title; the plain hub keeps the line marks above. When a tool's
emblem changes, re-import it the same way. The SCOPE skin's own painted emblem lives at `assets/brand/scope/emblem-dark.png` (512 px, derived from the full-size `assets/brand/scope-emblem-transparent.png`)
and, when one exists, `emblem-light.png`; without them the skin falls back to `scope.svg`.
