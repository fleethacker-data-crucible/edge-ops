# FleetHacker Suite: 30/60/90 Day Roadmap (Public Summary)

> This is a public summary. The full plan, including partner and resourcing details, is maintained internally by the FleetHacker team.

## Goal

Take the FleetHacker utilities from hackathon go-live to a fleet deployment, including the remaining shipboard (CANES) install path.

## Tech-stack constraints

Every FleetHacker utility, with edge-ops as the hub:

- Runs under Windows PowerShell 5.1
- Uses a Chrome or Edge browser engine for its interface
- Needs no admin rights (runs in user context)
- Works fully offline
- Listens only on localhost; makes no network calls
- Ships under the MIT license as packaged release assets with SHA256 hashes

## Current state by environment

| Environment | What it is | Status |
|---|---|---|
| NMCI | Navy Marine Corps Intranet shore desktops | Confirmed |
| Nautilus Endpoint Devices | Flank Speed endpoint devices | Confirmed |
| Nautilus Virtual Devices | Flank Speed virtual desktops | Confirmed |
| CANES (afloat) | Shipboard network | Gap: needs an approved install and hosting path |

A CANES install path is being pursued through a partner program; selection is in progress.

## Milestones

| Milestone | Date | Goal |
|---|---|---|
| Day 0 | Thu Nov 5, 2026 | Hackathon go-live |
| Day 30 | Sat Dec 5, 2026 | CANES install path selected |
| Day 60 | Mon Jan 4, 2027 | Test deployment complete |
| Day 90 | Wed Feb 3, 2027 | Fleet deployment |

### Day 30: select the CANES path

- Compare candidate install paths against criteria: reaches CANES unclassified workstations, accepts Windows PowerShell 5.1 user-context tools, has an inheritable accreditation path, and time to first test install
- Choose a primary path and a backup
- Package inventory: each utility, version, SHA256, SBOM, offline install notes

**Exit criteria:** path selected and a test install agreed.

### Day 60: test deployment

- Install on a CANES test or lab enclave
- Run the Sea-Trials checklists there and export results
- Accreditation touchpoints (RMF/ATO)
- Security artifacts: SBOM, SHA256 manifest, STIG and scan results, data-flow showing localhost-only and no network
- Install guide and rollback steps for shipboard admins

**Exit criteria:** all critical Sea-Trials checks pass on the CANES enclave; security package accepted; go or no-go for fleet deploy.

### Day 90: deploy

- Deploy to the first ship or ships through the chosen path
- Training: short user guide and a session for shipboard IT and users
- Support: issue handling, how fixes reach ships offline, release cadence
- Feedback loop: issue intake from ship and shore users

**Exit criteria:** suite in use on at least one CANES ship; support owner in place; next-phase plan agreed.

## Risks and mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Accreditation: no ATO or RMF path yet for CANES | High | Prefer a path with an inheritable accreditation; engage security reviewers early |
| Resourcing: small volunteer team | Medium | Document builds and releases; keep scope to one lab enclave if needed |
| Technical fit: some CANES delivery channels are Linux/container-based; the suite is Windows PowerShell 5.1 | Medium | Target CANES Windows workstations first |
| Shipboard connectivity: limited or no bandwidth at sea | Medium | Offline packages with SHA256; install pierside or by media; no network calls |
| Ship schedules and configuration differences | Medium | Pick the first hull early; test against its CANES baseline |

## Background reading

- "NAVWAR deploys the Navy's first Application Arsenal (CANES)", Navy Press Office news story, article 2735561, 2021. Cited by title because the fleet-gate check does not allow service hostnames in the repo; search the title on the Navy press site.
- "CANES in a shore cloud lab for app integration", CHIPS magazine (DON CIO), article ID 12128. Cited by title for the same reason.
