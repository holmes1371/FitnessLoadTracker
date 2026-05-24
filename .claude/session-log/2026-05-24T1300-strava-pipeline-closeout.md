# 2026-05-24 — Strava integration pipeline complete, #4 closed

- #4 (Strava OAuth + sync) closed and moved to Done; full post-mortem in `completed/4.md`. Three landed PRs: #8 (4a OAuth+Keychain), #9 (4b sync+first test pack), #11 (4c idempotency+atomic write).
- Test convention codified in CLAUDE.md: per-feature regression pack — Swift in XCTest target via Swift Testing, shell in `<dir>/tests/`. Every feature adds regression tests; agents do NOT smoke-test inline as a substitute.
- New issue #10 filed (Todo): differentiate "No match" causes in sync UI (UX polish deferred from #4b verification).
- **Next pickup**: #5 Phase 3 (Background App Refresh). Scope filed; iOS won't honor "exactly midnight" — `BGAppRefreshTask` gives "roughly daily" cadence at iOS's discretion. Free personal team's 7-day re-sign issue will bite weekly; that's when the $99 decision sharpens.
- Open thread for CLAUDE.md: Tom verifies on working branch *before* PR, so close-out can be agent-authorized on merge (not deferred for separate Tom verification). Current CLAUDE.md assumes test-after-merge; worth a small rewrite of the relevant Session-discipline bullets.
