# Judges brief

The infographic slide deck that positions the whole Data Crucible suite against the six Fleethacker Norfolk use cases, for the judges. 23 slides, 16:9. Built 5 November 2026 from the comms win plan (1 November re-grade), the heavy-lift and consolidation proposals, the Fleet Relationship Map, Crow's Nest scoring, bridge-warden's event rules and evaluation report, PacketRat's path-to-fleet and human-authority pages, the 3 November ATO assessment, the 4 November 30/60/90 roadmap, and the demo videos in this repository.

**Live deck (present, comment, export to PowerPoint or PDF):** https://claude.ai/artifact/Lwb5XJrtcbxRRPyZTvRgmZ (private until shared from its Share menu).

This copy lives in edge-ops so the hub's GitHub Pages site can serve it. The source of record, including the PowerPoint and PDF exports (too large for this repo's gate), is `judges-brief/` in the Commissioning repository.

## What is here

| Path | What it is |
|---|---|
| `index.html` | Redirects to `judges-brief.html`, so the folder works as a GitHub Pages URL: `https://fleethacker-data-crucible.github.io/edge-ops/judges-brief/` (the site build copies this folder to `_site/judges-brief/`). |
| `judges-brief.html` | Self-contained viewer: all 23 slides, scaled to the window, videos playable. Download it with the `assets/` folder beside it and open it in a browser; GitHub shows only its source. |
| `SPEAKER-NOTES.md` | The speaker notes, one entry per slide. |
| `deck.json` | The slide order, sections and typefaces (Exo 2 and IBM Plex Sans, from Google Fonts). |
| `slides/<id>.html` | One file per slide in the Slides artifact format: a single `<section>` with inline styles, the notes in a trailing `<aside>`. Asset references are relative paths into `assets/`. |
| `assets/emblems/` | The repo emblems and the Data Crucible emblem, downscaled to 420 px. |
| `assets/clips/*.vtt` | English captions for each demo excerpt, cut from the demos' own subtitle files; the viewer shows them by default. The full transcripts are the `.srt` files beside the full demos. |
| `assets/clips/` | 720p excerpts of the demo videos: the full pitch (1:40) and opening scene (0:37), and the first 40 seconds of each of the 16 tool demos, with a poster frame each. The full demos are in the `*-demo/video/` folders. |

## Slide order

1. Cover
2. The pitch (video) and opening scene
3. Bottom line up front
4. The locked-down workstation we build for
5. The suite: how the apps use each other
6. Six use cases mapped to the parts that already run
7. Paperless Underway (challenge 36), Tracks A and B
8. AI automated systems (challenge 9): Bridge Warden
9. MORDECAI (challenge 16): the shared-actuator case
10. Message traffic task and event extraction (challenge 24)
11. Electronic OPTASK parser and timeline (challenge 12)
12. CASREP Command (challenge 8)
13. Human authority across the suite (Rule 6)
14. Fleet-Ready Definition of Done scorecard and gap tools
15. Judging rubric with evidence per criterion
16. What judges can run and verify (Rule 3)
17. to 20. Demo reels, four tools each
21. Path to fleet: 30/60/90 and the ATO findings
22. Friction log and OSW ROI mapping
23. The ask

## Status labels

Every use-case slide marks what was live before 4 November and what is event work, per Rule 7. The rubric totals and the Definition of Done counts are the win plan's own estimates from the 1 November re-grade and are labeled as estimates on the slides. Crow's Nest verdicts are the 28 October offline snapshot; its matching is keyword overlap.

## Rebuilding

The slides were authored by hand in the Slides artifact format and copied here with `/_blob/<id>` references rewritten to `assets/` paths. The clips were cut with ffmpeg: `-t 40 -vf scale=1280:-2 -c:v libx264 -crf 27 -c:a aac -b:a 64k -ac 1`, poster frame at 6 seconds.
