# netsh request-queue fixtures

`requestq-en-real-8845.txt` is a real capture of `netsh http show servicestate view=requestq`, taken by Zombie Admin
on Windows PowerShell 5.1 as a **standard (non-admin) user** on an en-US machine. netsh exited 0 and printed the full
English layout. A FleetPort test listener (pid 9720) held `http://localhost:8845/`, next to the Windows FDResPub
service queue on `*:5357`. The only edit is scrubbing: the FDResPub URL's device GUID is replaced with zeros. Line
endings (CRLF) and trailing spaces are kept as netsh wrote them.

Every other `requestq-*-real-*` file is that capture with one deliberate edit, so the layout stays real:

| File | Edit | Expected |
|------|------|----------|
| `-8845-otherpid` | queue pid 9720 -> 5555 | refuse, "held by pid 5555" |
| `-8845-emptyqueue` | no process, attached 0 | refuse |
| `-8845-twoprocs` | two processes, attached 2 | refuse |
| `-8845-malformed` | `ID 9720 image` (no colon/comma) | refuse |
| `-8845-ambiguous` | extra `HTTP://+:8845/` | refuse |
| `-8845-legacy` | extra `HTTP://LOCALHOST:8845/legacy/` (Zombie Admin's A4 case) | refuse |
| `-8845-twoqueues` | a second queue (pid 9800) on `127.0.0.1:8845` | refuse |
| `-8845-badurl` | an unparseable URL line | refuse |
| `-25000-ipbound` | a TalkForge-style queue (pid 10836) with `HTTP://LOCALHOST:25000/` and the IP-bound `HTTP://127.0.0.1:25000:127.0.0.1/` | 10836 |
| `-25000-ipbound-only` | that queue with only the IP-bound loopback form | 10836 |
| `-25000-ipbound-lan` | `HTTP://10.0.0.5:25000:10.0.0.5/` next to localhost | refuse |
| `de-real-8845` | header line translated to German | refuse (English only) |

`requestq-accessdenied.txt` is hand-written error text. A standard user is **not** denied on en-US Windows (see the
real capture); this file only checks that error text is refused.
