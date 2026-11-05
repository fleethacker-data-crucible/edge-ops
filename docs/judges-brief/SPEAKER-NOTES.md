# Judges brief: speaker notes

One entry per slide, in deck order.

## Slide 1: cover

Open with the thesis: we did not build six prototypes for six use cases. We brought one suite that already runs on NMCI and Nautilus devices in user context, and we show how its parts answer each use case. Everything on the following slides is marked as built before the event, built at the event, or planned, per Rule 7.

## Slide 2: pitch

Let the pitch play with sound when the slide comes up; it is one minute forty. The opening scene is the longer film’s first shot and plays on click if there is time. Then move straight to the bottom line.

## Slide 3: bluf

Three claims, each backed later in the deck. The rubric numbers are our own estimates from the 1 November win plan, re-graded against every repo’s default branch. Say so: Rule 8 forbids a sales pitch, so every number here is sourced and labeled an estimate.

## Slide 4: constraint

This is the constraint every other team hits on day one. We have lived inside it for months. The 25 October workstation run on Windows 11 Enterprise as a standard user proved loopback servers start without a URL reservation or admin rights. Rule 9 asks teams to consider portability, limited connectivity and shipboard constraints; this slide is our answer.

## Slide 5: suite

Read it bottom up. Local engines serve models on the machine. Fairlead routes every AI request to those engines first, with Lazarette holding the keys and Bridge Warden deciding what an agent may do. The work apps sit on top and hand files to each other as plain, versioned JSON and CSV, never over a network. A person or an agent drives all of it from the browser or the Fleet Action CLI.

## Slide 6: matrix

Every card says what was live before Nov 4 and what is event work. That split is Rule 7, and judges reward it. The evaluator is our own tool, Crow’s Nest, which scores each portal use case against the org’s repos; its matching is keyword overlap, so a low score means the words did not match, not that the parts do not exist. The next six slides take one use case each.

## Slide 7: uc-paperless

This is the anchor entry and the one the challenge sponsors said drew the strongest fleet demand. Both tracks run from the existing parts. The two event-work items, Quill and Tideline, are the ones that close the Fleet-Ready Definition of Done: form validation and sync on reconnect. PacketRat’s burden record exists so a Sailor can time the task by hand, then with the tool; the measured number is the one we put in front of the Warfighting criterion.

## Slide 8: uc-ai-systems

Bridge Warden is a governance layer, not another agent, which is exactly what the challenge asks for. The agents themselves call Phoenix LAI on the local GPU, so the whole thing runs with the network unplugged. Be clear that these are simulation numbers; the 60-day plan is adapters for two real autonomy stacks and measurement against a no-Warden baseline.

## Slide 9: uc-mordecai

MORDECAI and challenge 9 are the same problem from two angles: a dozen independently built AI systems sharing physical resources with nobody arbitrating. Bridge Warden already treats every actuator as a resource and every order as an intent, so the contradictory-order case is a conflict-detector scenario, not a new product. The authority card on this slide is the Rule 6 statement judges look for.

## Slide 10: uc-message-traffic

The challenge names human error: tasks missed in dense traffic, schedule disruption, last-minute preparation. Our answer is not to remove the human but to make sure every extracted task stays tied to the line it came from and lands in a queue a person clears. The honest gap is the formatted Navy message grammar; PacketRat today is built around email, and the parser is the event work.

## Slide 11: uc-optask

This use case and the previous one share a pipeline on purpose: one parser, one queue, one hand-off format, and the dashboards and alerts already exist. The event work is a grammar and a dashboard definition, which is why a seven-person team can show it between kickoff and downselect. If the judges ask what we did at the event, this is the clean answer.

## Slide 12: uc-casrep

This is the use case where we are most clearly assembling rather than demonstrating prior work, so say so first. The parts exist and are each tested; the integration is the event deliverable. The judges’ question will be whether a seven-person team can assemble it by downselect; the answer is that the hand-off formats between these tools are already defined and versioned, which is the hard part.

## Slide 13: authority

The Naval Agentic AI category requires a team to define what the agent may do, may never do, needs approval for, how it is logged and how it is stopped. This table is that definition for the six tools judges will see in the demos. The logs are tamper-evident, not tamper-proof, and the docs say so; do not claim more than the code proves.

## Slide 14: dod

Show the judges the scorecard we grade ourselves on. Seventeen of nineteen run offline today; the two weak rows, sync on reconnect and the one-page path to fleet, are exactly the two gap tools we prioritized. Tideline is one PowerShell module every app can share, and PacketRat’s path-to-fleet page is the template the rest copy. Honesty here earns the Judges’ Discretion points a polished claim would lose.

## Slide 15: rubric

Walk the table top to bottom and point at the demo that proves each row. The numbers are estimates and the slide says so; what matters is that each criterion has a named artifact behind it. The three rules at the bottom are the ones the win plan found cost points when missing.

## Slide 16: evidence

Rule 3 says concept slides alone are insufficient. Everything on this slide is something a judge can click, run or re-run at the table. Offer the hash-chain verify as the one-minute demo if time is short: edit a line, run verify, see the break reported.

## Slide 17: reel1

Clips are muted so four can run at once; click one to pause the others’ attention and talk over it. If a judge wants depth on one tool, the full demo is six to seven minutes and lives in Commissioning, rendered by Signal-Gun from the repo’s DEMO.md.

## Slide 18: reel2

These four carry Paperless Underway Track B and the CASREP story: the record store, the approval gateway, the dashboard and the vault. Point out that the same key, set up once in the Halyard demo, is reused by every other tool in the reel.

## Slide 19: reel3

These are the Paperless Underway Track A capture tools and the CASREP chop flow. Capstan and SnapShackle also made the demo videos themselves, with TalkForge narrating: the suite documents itself with its own tools.

## Slide 20: reel4

Phoenix and Windlass are the reason the whole suite can go offline: they are the engines behind Fairlead’s local routes. Data Noodler is the flat-file engine Semaphore’s workbench grows into. Shellback is the evidence for the digital-workforce ROI.

## Slide 21: path

Rule 11 wants a mission owner, a technical owner, a next experiment, resources and a 30/60/90. All five are here, with the dates. Lead with the three confirmed environments, then own the CANES gap and the ATO findings before a judge raises them. The team that names its own blockers is the one judges trust with ninety days.

## Slide 22: friction

Rule 10 asks for policy, data, authority, infrastructure, acquisition and technical barriers with responsible organizations and recommended actions. These five are the ones we hit before kickoff; the event log adds to them. Every OSW ROI gets a concrete artifact, not an adjective.

## Slide 23: ask

Close on the ask from the pitch video, then stop talking. If there is one question to invite, it is “show me the hash chain break” or “unplug the network”; both are rehearsed.
