# Architecture — FitnessLoadTracker

## Problem

Tom records workouts via the Strava app, not Apple Watch native, because Strava has a live safety beacon for outdoor rides that Apple Watch has no equivalent for. Strava syncs workouts into Apple Health via its own integration, **but without the iOS 18 `workoutEffortScore`**. As a result, the Apple Watch Ultra 2's training-load bevel and the Fitness app's Training Load view stay empty even though Strava already computes an equivalent score (Relative Effort, API field `suffer_score`).

Goal: an automated pipeline that maps Strava's `suffer_score` per activity to Apple's 1–10 effort scale and writes it to the matching HealthKit workout, so the watch bevel populates without manual RPE entry.

## Rejected approaches

### Apple Shortcuts (original plan)

The first idea was: Python on GitHub Actions cron → JSON in repo → iOS Shortcut on phone reads JSON → writes effort. Shortcuts can't do it:

1. **`Log Health Sample` doesn't expose `workoutEffortScore`** as a selectable type, and per Apple Community reports a variable can't be passed into the action's Type field anyway.
2. Even if it did, the sample would float free in HealthKit. Attaching it to a workout requires `relateWorkoutEffortSample(_:with:activity:completion:)` — API-only, no Shortcut equivalent. The Fitness app's effort slider calls this API internally.

Verified against:
- [Apple Developer Forums — Workout Effort Scores](https://developer.apple.com/forums/thread/764884)
- [Sasquatch Studio — Reading/Writing Workout Effort Scores (2025-04)](https://sasq.ca/blog/2025/4/28/reading-writing-workout-effort-scores)
- [Apple Community — Shortcuts Log Health Sample](https://discussions.apple.com/thread/255593910)

### Existing third-party apps

HealthFit, RunGap, SyncMyTracks all sync workouts and HR between Apple Health and Strava, but **none write `workoutEffortScore` from external sources**. HealthFit *exports* the Apple effort to CSV (release notes through Feb 2026) but never imports effort from Strava. Confirmed via App Store descriptions and developer forum threads.

## Chosen architecture

Single native iOS companion app:

```
[Strava API] ──→ [iOS app on Tom's iPhone]
                       │
                       ├─ refresh OAuth, pull recent activities
                       ├─ read existing workouts from HealthKit
                       ├─ match by start_time + duration + type
                       └─ write workoutEffortScore + relateWorkoutEffortSample
```

Triggered by iOS Background App Refresh plus a manual "Sync now" button. Strava refresh token stored in iOS Keychain.

### Why one component (no server)

A native iOS app handles Strava OAuth refresh + activity pulls + HealthKit writes itself. The original plan's GitHub Actions middleman + JSON-in-repo existed only because Shortcuts couldn't do OAuth. With Shortcuts off the table, the middleman becomes dead weight. Single component: fewer moving parts, no JSON to manage, no cron to maintain, refresh token in iOS Keychain (more secure than env vars).

If BG Refresh proves unreliable in practice, server-side cron is a fallback — measure first.

## Cross-machine workflow (Windows ↔ Mac)

Tom works primarily on a Windows 11 PC. iOS work (Xcode) requires the MacBook Pro. Handoff via the shared repo + `CLAUDE.md` (auto-loaded) + the latest 1–2 session-log files. Any agent on either machine reaches steady state from those plus the design note(s).

- **Windows work**: repo + issue + board management, any throwaway Python sandbox for Strava API exploration.
- **Mac work**: everything in `ios/` — Xcode project, Swift code, builds, sideloading.

## Apple Developer / signing

No paid Apple Developer account ($99/yr) for v1. Free personal team. HealthKit capability *should* work with free provisioning (~90% confidence — verified at first Xcode build). Real cost of free: provisioning expires every 7 days; the app stops launching until re-run from Xcode (~30s chore). Decision: start free, validate the architecture, then re-evaluate $99 once we know it works.

## Strava → Apple effort calibration

Strava's `suffer_score` is HR-zone-weighted, uncapped: ~30 easy, ~150 hard, 200+ very hard. Apple's `workoutEffortScore` is 1–10 RPE.

v1 calibration is a dumb bucket function:

| `suffer_score` | Apple effort |
|---|---|
| < 30 | 2 |
| 30–60 | 4 |
| 60–120 | 6 |
| 120–200 | 8 |
| ≥ 200 | 10 |

Tune after a week of real data against subjective RPE. Locked decision: no perceived-exertion prompt in the app — the whole point is to remove that friction.

## Workout matching

Workouts arrive in HealthKit via Strava's own Apple Health integration (Strava → Apple Health, separate from this app). Matching key from Strava activity → HealthKit workout:

```
start_time within ±60s
duration within ±60s
activity_type matches
```

Should be unique in practice for one user. If multiple matches: skip with a warning surfaced in the app's status UI.

## Phase plan

Tracked as GitHub issues on the project board (https://github.com/users/holmes1371/projects/3):

- **Phase 0**: Register Strava API application (Tom action; walkthrough in issue body).
- **Phase 1**: Smallest HealthKit-write proof — hardcoded effort 7 on most-recent workout. De-risks entitlement + bevel render before any Strava work.
- **Phase 2**: Strava OAuth + activity pull + matching + write.
- **Phase 3**: Background App Refresh wiring + Sync-now button + status UI.

Phase 1 doesn't depend on Phase 0 (no Strava credentials needed for hardcoded write). Phase 2 depends on both 0 and 1. Phase 3 depends on Phase 2.

## Open questions

None blocking Phase 0 or Phase 1. Open for Phase 2:
- Exact OAuth callback redirect for the one-time browser handoff (likely a custom URL scheme registered on the iOS app, so Strava's redirect lands back in the app — confirm at implementation time).

## Test fixtures needed

Deferred until Phase 2. For Phase 1, a manual test against Tom's most-recent workout is sufficient; no unit tests for a 50-line proof.
