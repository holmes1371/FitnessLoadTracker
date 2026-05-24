# Completed items archive

One file per closed GitHub issue: `completed/<issue-number>.md` (e.g. `completed/12.md`).

**Cadence**: written **immediately** on issue close-out — same turn the issue gets closed, before moving on. Not "end of session." Not "next commit." The current turn has full context on decisions, bugs, and trade-offs that don't survive cleanly into commits / issue bodies / design notes alone.

**What to capture**:

- **What was built** — the actual implementation, what landed in which PRs.
- **Decisions worth preserving** — the *why* behind non-obvious choices, especially trade-offs Tom called.
- **Trigger and design history** — what prompted the work, what alternatives were considered and ruled out.
- **Workflow gotchas** — anything that surprised the agent (test fixture quirks, tooling traps, etc.) that a future session would benefit from knowing.
- **Follow-ups** — known not-in-scope items, with the trigger that would bring them back into scope.

**No trim discipline**: this is an archive. Files accumulate forever — searchable repo-local history beats navigating closed issues.

**Grep before re-deriving**: when starting work that overlaps a closed item, `grep -r 'pattern' completed/` first.
