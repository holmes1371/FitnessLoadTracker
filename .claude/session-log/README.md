# Session log

One file per session, named `YYYY-MM-DDTHHMM-<branch-slug>.md` (e.g. `2026-05-24T0900-framework-bootstrap.md`).

**Content**: ≤5 bullets, ≤1 sentence each. Cold-pickup state only — what was the session about, what landed, what's the next-step hand-off.

**Cadence**: one file per session, rewritten in place between commits within that session. New session → new file.

**Trim at session start**: if this folder has more than ~10 files or any file is older than ~14 days, delete the older ones. Durable signal lives in commit messages, `completed/*.md` post-mortems, design notes, and closed issues — the session log is recency-only.

**Why per-file**: avoids merge conflicts that a single-block-in-CLAUDE.md scheme produces when two agents work the same day on different branches. ISO date + 24-hour `HHMM` so files sort newest-last alphabetically; branch slug disambiguates parallel writes.
