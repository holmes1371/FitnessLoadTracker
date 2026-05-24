# Design notes

Short design notes for non-trivial features, one file per feature: `design/{feature-name}.md`.

Purpose: a fresh session should be able to pick up mid-feature from the note plus the last commit, without re-litigating decisions already made with Tom.

A good note captures:

- **Scope** — what is in, what is explicitly out.
- **Decisions already made** — with the reasoning, so edge cases can be judged later.
- **Open questions** — anything still pending Tom's input before coding.
- **Test fixtures needed** — so the test plan is visible before implementation starts.

Keep notes short. If something changes mid-feature, update the note in the same commit as the code change — do not leave stale prose.
