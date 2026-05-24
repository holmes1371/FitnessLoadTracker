# 2026-05-24 — Framework bootstrap

- Brought the LawTracker session-discipline framework over: `CLAUDE.md`, `design/README.md`, `completed/README.md`, `.claude/session-log/README.md`, Python-flavored `.gitignore`. Shipped via PR off `claude/admiring-heisenberg-c7bde7`, merged as `6b2f5dc`.
- GitHub project board IDs for project #3 (`PVT_kwHOAmwjSM4BYpmV`, status field `PVTSSF_lAHOAmwjSM4BYpmVzhTt5Jg`, options Todo/In Progress/In Testing/Done/Descoped) baked into `CLAUDE.md` — no need to re-fetch. Board status column "In Testing" has a capital T (vs LawTracker's lowercase "In testing").
- Stripped from the template: Fly deploy / `LAWTRACKER_DB_URL` / scout-render CLI references, the legacy `Item N` + `completed/legacy-*` conventions, and the "deterministic Python, LLM does judgment only" standing rule (LawTracker-specific). Source-code path left TBD until the first slice of code lands.
- Next session pick-up: no active issues yet — backlog at https://github.com/holmes1371/FitnessLoadTracker/issues is empty. First real work session should file the first GitHub issue(s) before coding.
