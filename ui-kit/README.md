# FleetHacker UI Kit v0.1.0

One CSS file and one JS file. No npm, no build step, no CDN, no web fonts. It works offline from `file://` in Chrome-engine browsers (Chrome and Edge).

## Files
| File | Purpose |
|---|---|
| `kit.css` | Design tokens (`--fh-*`) for dark (default) and light themes, base styles and reset, layout, nav, buttons, forms, tables, cards, badges, alerts, tabs, disclosure, dialog, toast, focus, reduced-motion, high-contrast and forced-colors |
| `kit.js` | A classic script, not an ES module, so it loads from `file://`. Adds `window.FH` with theme toggle, dialog, tabs, disclosure and `FH.toast()` |
| `assets/` | Brand images reduced from `dumping-grounds` (coin logo, favicon, molten-metal banner) |
| `demo.html` | Shows every component. Open it directly in a browser |
| `check-contrast.py` | Checks every token color pair against WCAG 2.1 AA |
| `VERSION` | The kit version. The same version is stamped at the top of `kit.css` and `kit.js` |

## Adopting it in a tool
1. Copy the whole `ui-kit/` folder into the tool, for example as `ui/kit/`. Do not hotlink it, because each tool keeps its own copy for offline use.
2. Add `<link rel="stylesheet" href="kit/kit.css">` and `<script src="kit/kit.js" defer></script>`.
3. Use the `fh-` classes and the markup patterns in `demo.html`. Apply tool-specific CSS after `kit.css`, and override tokens only if you re-run the contrast check.
4. Record the kit version you copied, for example in the tool's README. To upgrade, replace the folder.

## Accessibility rules (Section 508 / WCAG 2.1 AA)
- Set `<html lang>`, give every page a unique `<title>`, add a skip link (`.fh-skip`) to `#main`, and use landmarks (`header`, `nav[aria-label]`, `main`, `footer`).
- Every input needs a `<label for>`. Connect hints and errors with `aria-describedby`, and mark invalid fields with `aria-invalid="true"`. Never rely on color alone to convey meaning.
- Use `<button>` for actions and `<a href>` for navigation. Never remove the focus ring; the kit uses `:focus-visible` with 3:1 or better contrast.
- Tables need a `<caption>` and `th[scope]`. Give a scrolling wrapper `role="region"`, `tabindex="0"` and a label.
- Dialogs use native `<dialog class="fh-dialog" aria-labelledby>`. Esc closes the dialog and focus returns to the button that opened it.
- Tabs follow the WAI-ARIA APG pattern: arrow keys, Home and End move between tabs, and focus uses a roving tabindex.
- Toasts go to a polite live region, or an assertive one for `type:'bad'`. They pause on hover and focus, and each has a dismiss button.
- Images need `alt` text, or `alt=""` if they are decorative.
- Text contrast must be at least 4.5:1, and UI borders and focus indicators at least 3:1. Run `python3 check-contrast.py` after you change any token.
- Run axe-core with headless Chrome from a temporary folder outside the repo, and fix every violation before you open a PR.
