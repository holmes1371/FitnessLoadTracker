# 2026-05-31 — #39 closed (surface possible duplicate workouts)

- **Read-only duplicate detection during sync** (#39): clusters the per-activity HK workouts already fetched by same type + start ±60s + duration ±60s, surfaces clusters of 2+ in a new orange "Possible duplicates" section. Can't delete other apps' samples (#12), so display-only — Tom deletes in Health.
- `DuplicateDetection.swift` is a pure union-find clusterer (distance shown but NOT a match key, so indoor rides lacking native distance still pair); `SyncOrchestrator.collectDuplicates` runs off the existing proxy-filtered fetch, deduped by member-UUID cluster id.
- `HealthKitManager`: `sourceName`/`distanceMeters` helpers + read auth for `distanceWalkingRunning`/`distanceSwimming` (re-triggers Health permission sheet once).
- **Scope: ride-along only** — flags dupes within synced activities' recent windows; historical outliers need a re-sync. Wide-scan button is a possible follow-up.
- Tom synced on-device, no dupes surfaced (none present) — positive path unverified for lack of a real dupe; shipped on test-suite trust, he'll watch for it. Full XCTest green; PR raised with `Closes #39`.
