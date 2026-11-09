# Turnkey connections: how Fleet apps reach Fairlead, TalkForge and Lazarette

Adopted 2026-11-08. Goal: a person unzips the Fleet apps, sets a Lazarette passphrase once, and everything else connects by itself. No pairing codes to paste, no client keys to install, no token items to pick, no share names to type.

## What the person does

1. Opens Lazarette the first time and sets a passphrase. That is the only setup screen.
2. Uses any Fleet app. Fairlead (models) and TalkForge (voice) start by themselves when an app needs them.
3. The first time an app needs a real secret (a database password, a GitHub token, a provider key), Lazarette shows one prompt: **"Semaphore wants your SMDATS database password. [Allow always] [Just this once] [Deny]"**, with a box to add the secret there if it is not in the vault yet.

## The four rules

### 1. Local services use a local token, not a hand-shared one

Fairlead and TalkForge only need to know "this request came from an app of the same Windows account on this PC". Each service makes a random token on first start and keeps it in a file only that account (and SYSTEM) can read:

| Service | File | Accepted as | Off switch |
| --- | --- | --- | --- |
| Fairlead | `%LOCALAPPDATA%\Fairlead\local-token` | a client key from loopback only, named by `X-Fairlead-Label` | `FAIRLEAD_LOCAL_TOKEN=off` |
| TalkForge | `%LOCALAPPDATA%\TalkForge\local-token` | the bearer token, alongside any token TalkForge was started with | `TALKFORGE_LOCAL_TOKEN=off` |

An app reads the first line of the file and sends it. Configured keys and tokens keep working and take priority (Fairlead: the `Fairlead/<App>` credential first; TalkForge: an explicitly configured token first).

Why this is as safe as before: other accounts cannot read the file. A program running as the same user could, but it could equally read that user's Credential Manager or the vault-derived token from their session, so a key installed or shared by hand adds no protection there. It also removes the failure where an unrelated secret (an OpenAI key) was picked as the TalkForge token.

### 2. Lazarette guards only real secrets, and asks at the moment of need

Apps read secrets from the running Lazarette through the tools protocol (`docs/TOOLS.md` in Lazarette, `tools/Lazarette.Client.ps1`). The first request from a new app is the pairing: the app asks, Lazarette shows an Allow prompt (app name, program path, PID, a matching number the app also shows), and on Allow the pairing secret is sent encrypted to a key the app made for that request. No code is copied. Apps never load Lazarette's engine (`lib\Lazarette.ps1`) into their own process.

"Paired" means Lazarette says so: an app checks with Lazarette's live state call, never only with its local pairing file. A stale pairing becomes a new Allow prompt, not an error.

### 3. Apps start what they need

An app that needs Fairlead or TalkForge and finds nothing on its port starts it through FleetPort's `Start-FleetService` (`tools/fleet-port/README.md`, "Starting a shared service"), then waits for it. It checks `/__fleethacker/id` (tool name, the PID that holds the port, and the reported `path`) before sending any token. Fairlead outlives the app that started it; TalkForge stops itself after 30 idle minutes.

### 4. One place shows the state

Each app with a UI shows a small Connections status: Lazarette, Fairlead, Voice. Each one is green, or red with one Fix action that does the right thing (start the service, or send an Allow request to Lazarette).

## Who changes what

Survey of 2026-11-08 (file references are from that day's checkouts).

| App | Fairlead today | TalkForge today | Lazarette today | Change |
| --- | --- | --- | --- | --- |
| **Fairlead** | the router | routes `/v1/audio/speech` to TalkForge with a configured key | own `/peer/fairlead/v1` pairing (pasted code), reads Lazarette-Lite items | Make and accept its local token (Fairlead#75). Report `path` in its id (Fairlead#74). Read TalkForge's local token for voice routing. Move to the tools protocol for upstream secrets. |
| **TalkForge** | | the speech server | `--token-from lazarette` loads the engine in-process | Make and accept its local token (talkforge#44). |
| **Lazarette** | peer server for Fairlead | starts TalkForge with the `talkforge-api` item as token | the vault and tools protocol | Pair from the tool with an Allow prompt; live paired check; pin the `-File` script; Fairlead as an ordinary tool. Use TalkForge's local token instead of a token item; restart TalkForge when its token changes. |
| **Semaphore** | `Fairlead/Semaphore` or `SEMAPHORE_AI_KEY`; strict id check; starts Fairlead | `TALKFORGE_TOKEN` share from Lazarette; starts TalkForge | tools protocol, copied client | Fall back to Fairlead's local token; use TalkForge's local token; pair from the tool; live paired check; Connections panel; `Start-FleetService`. |
| **Halyard** | `Fairlead/Halyard`; checks `/v1/health`; can start Fairlead | starts its own TalkForge on 25008 with a per-run token | loads `lib\Lazarette.ps1` in-process and unlocks in its console | Stop loading the engine; use the tools protocol. Fall back to Fairlead's local token; check `/__fleethacker/id`. Use the shared TalkForge (local token) instead of its own copy. |
| **Gangplank** | `GANGPLANK_AI_TOKEN`, `LLM_TOKEN` or `OPENAI_API_KEY`, else its own store; does not read `Fairlead/Gangplank` | | loads `lib\Lazarette.ps1` in-process | Read `Fairlead/Gangplank`, then the local token. Stop loading the engine; use the tools protocol. Check the id; start Fairlead when needed. |
| **PacketRat** | `Fairlead/PacketRat`; starts Fairlead (`--console --no-tray`) | voice files on disk only | | Fall back to the local token; check the id; start through `Start-FleetService` with the tray. |
| **Bowerbird** | `Fairlead/Bowerbird` only; "install a key" error | | | Fall back to the local token; check the id; start Fairlead when needed. |
| **SnapShackle** | `Fairlead/SnapShackle`; "Start Fairlead" error | | | Fall back to the local token; check the id; start Fairlead when needed. |
| **Scrimshaw** | key typed into the browser each session | | | Its local server reads the local token and calls Fairlead for the page, so nothing is typed. |
| **Shellback** | optional preset; key sealed in the browser | | | Same as Scrimshaw: a local server-side call with the local token, or keep the browser key as an option. |
| **Lazarette-Lite** | Fairlead reads its Credential Manager items directly | | is a vault | No change. |

No real usage (copies or demo files only): Capstan, Commissioning, Signal-Gun, bridge-warden, Windlass (a backend Fairlead calls).

## Checklist for an app

- [ ] Fairlead key: `Fairlead/<App>` credential if present, else the first line of `%LOCALAPPDATA%\Fairlead\local-token`. Always send `X-Fairlead-Label: <App>`.
- [ ] TalkForge token: an explicitly configured token if present, else the first line of `%LOCALAPPDATA%\TalkForge\local-token`.
- [ ] Before sending either: `/__fleethacker/id` names the right tool, its `pid` holds the port, and its `path` is that process's executable or `-File` script.
- [ ] Nothing on the port: `Start-FleetService -Name fairlead|talkforge`, then wait; never tell the person to run a launcher.
- [ ] Secrets from Lazarette through `Lazarette.Client.ps1` only, pairing by request with Allow; never `lib\Lazarette.ps1` in-process.
- [ ] Never print, log or put on a command line any token or key.
