# Standards exceptions to flag (repos not changed)

The standard follows phoenix-lai and data-noodler. These patterns in the reference repos break a hard constraint (PS 5.1, no admin, offline, loopback-only bind; `localhost` counts as loopback), so they are **left out of the standard** and flagged for the owners. Nothing in the repos was changed for them.

| # | Repo | Where | Pattern | Constraint |
|---|---|---|---|---|
| 1 | phoenix-lai | `src/Providers.cs` (Phoenix Client) | can call any OpenAI `/v1` provider by URL, including cloud, when the user adds one (approved 2026-10-20 per `src/run.ps1`) | offline (opt-in, so this may just need a note) |

Other differences that are **not** hard constraints, noted only:
- Port overlaps (phoenix-lai 8765-8789, Lasso, Synapse) are resolved by the port ruling in [PORTS.md](PORTS.md).
- data-noodler `Data Noodler.lnk` uses a dev-machine icon path (`D:\Dev_Project_Repository\...`) and the working-directory-relative `server\server.ps1` (works only when started from its own folder), and runs without `-STA`.
- Both `.lnk` launchers use `conhost.exe --headless` (Windows 10 1809 or later). phoenix-lai's also compiles a tiny C# class with `Add-Type` in the launcher, which app-control policies that block runtime compile will stop.
