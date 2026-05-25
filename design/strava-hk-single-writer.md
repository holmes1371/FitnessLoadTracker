# Strava → HealthKit single-writer pipeline

## Problem

Today an indoor Peloton ride hits HealthKit twice: once from the Peloton iOS app (carries Watch HR), once from Strava's native HK integration after Peloton mirrors the ride to Strava. Issue #12 added a Peloton-over-Strava tiebreaker so the effort write lands on the Peloton workout, but the Strava duplicate still appears in HK and Tom deletes it manually in Health.app.

The deletion can't be automated — HK only lets an app delete samples it authored (verified via #12's POC).

## Decision

Eliminate the duplicate upstream rather than papering over it downstream. Two coupled changes:

1. **Disable Strava's native HK sync** (one-time Strava-app setting). After this, only true source apps (Peloton, Apple Watch, etc.) write to HK directly.

2. **App becomes the HK workout writer for Strava-only activities.** For each Strava activity pulled via API:
   - **HK match found** (e.g. Peloton twin within ±60s start/duration + same activity type): unchanged — attach `workoutEffortScore` via the current `relateWorkoutEffortSample` path.
   - **No HK match**: create a new `HKWorkout` from the Strava activity data, then attach effort.

Net effect: every Strava activity ends up in HK exactly once, with effort attached. No manual cleanup.

## Scope

### In

- Expand HK share-authorization to include `HKWorkoutType` and `HKQuantityType(.heartRate)` (currently only `workoutEffortScore`).
- New `HealthKitManager.writeWorkout(...)` that builds and saves an `HKWorkout` from a `StravaActivity` plus detail-endpoint fields, then writes per-second HR samples covering the workout's time range. Field mapping (see "Captured Strava fields" below for the full list):
  - Core `HKWorkout`: `startDate` from `start_date_local`, `endDate = startDate + moving_time`, `totalDistance` from `distance`, `totalEnergyBurned` from `calories`, `HKWorkoutActivityType` via the existing `Matching.hkActivityType(...)` map.
  - First-class HK metadata: `HKMetadataKeyAverageSpeed`, `HKMetadataKeyMaximumSpeed`, `HKMetadataKeyElevationAscended`.
  - Custom metadata (prefix `com.holmes.fitnessloadtracker.*`): `avgHeartRate`, `maxHeartRate`, `elapsedTime`, `avgCadence`, `avgWatts`, `maxWatts`, `weightedAvgWatts`, `kilojoules`, `deviceName`, `stravaActivityId`, `stravaWorkoutType`. Cycling-only fields (cadence/power/kj) and other optionals are only attached when Strava returns a non-nil value.
  - Per-sample HR: `HKQuantitySample` of type `.heartRate`, batched in a single `save([HKQuantitySample])` call.
- New `StravaClient.fetchActivityDetail(id:)` hitting `/activities/{id}` — needed for `calories` (detail-only) plus the broader metadata set above (`device_name`, `workout_type`, power fields).
- New `StravaClient.fetchActivityStreams(id:, keys:)` hitting `/activities/{id}/streams?keys=heartrate,time&key_by_type=true` for per-second HR data. Used to populate per-sample HR on the created HKWorkout.
- `SyncOrchestrator.process` routes `.noMatch` to: fetch detail → fetch streams → create workout → write HR samples → attach effort. New `ItemStatus` case (`.writtenAsNew(effort:)` or extend `.written` with a flag) so UI distinguishes "attached to existing" vs "app created + attached effort".
- Remove the Peloton/Strava tiebreaker in `Matching.swift:67-72` and the `pelotonBundleID`/`stravaBundleID` constants. With Strava→HK off, the Strava bundle stops appearing in candidates entirely — the tiebreaker becomes dead code.
- Remove `WorkoutCandidate.bundleID` (currently only consumed by the tiebreaker; rip it rather than leave it as dead weight).
- `MatchingTests` updates: drop the Peloton-vs-Strava-pair test cases.
- New tests covering the no-match-create path.
- User-side walkthrough on the issue: step-by-step to disable Strava→HK in the Strava iOS app, plus a fresh-activity smoke check confirming it stuck.

### Out (deferred)

- **Non-HR streams** (power, cadence, distance-time, altitude). Available from the same `/streams` endpoint by adding more `keys`. Tom's primary need is HR (drives the suffer-score model and the training-load bevel); other streams are nice-to-have but not motivated by the source problem. Add later if/when there's a concrete use case.
- **Backfill** of historical Strava-only activities that previously skipped as `.skippedNoMatch` while Strava→HK was on. Once native sync is off those activities have no HK twin; this issue does not retroactively create them. Could be a follow-up with a "backfill range" UI.
- **UI warning when Strava→HK is still on** (i.e. user forgot to disable). Detectable by spotting `com.strava.stravaride` in HK candidates. Possible follow-up; not blocking.

## Locked decisions

### Strava API endpoints per path

`SummaryActivity` (from `/athlete/activities`) covers most of what we need at workout-summary level: start, elapsed_time, sport_type, distance, total_elevation_gain, average/max heartrate. **`calories` is detail-only** (`/activities/{id}`). Per-second HR is **streams-only** (`/activities/{id}/streams?keys=heartrate,time&key_by_type=true`).

Decision: **detail + streams calls fire only on the no-match path**. The match-found path stays list-only — it just attaches effort. For each Strava-only activity that's 3 total calls (list batch + detail + streams) vs 1 for matched. Tom's volume is ~5-10 rides/week, mostly Peloton-twinned — well under Strava's 100/15min and 1000/day rate limits even on a 30-day backfill.

### Duration: `moving_time`, not `elapsed_time`

Strava distinguishes `elapsed_time` (wall-clock, includes auto-pauses) from `moving_time` (auto-pause excluded). `HKWorkout.duration = endDate - startDate`, so picking one forces the other into metadata. Decision: **`endDate = startDate + moving_time`**, with `elapsed_time` stashed as custom metadata. Tom's training-load reasoning is built on moving time (the time actually working), not wall-clock; this matches the Watch's "active duration" intuition and keeps HK's primary duration field aligned with the number that drives effort.

### Metadata breadth: pull more, accept some won't render

For every Strava field that's cheap to decode and might be useful later, write it to HK metadata even when no Apple UI surfaces it today. First-class metadata keys (`HKMetadataKeyAverageSpeed`, etc.) render in the Fitness app; custom keys under `com.holmes.fitnessloadtracker.*` won't but are recoverable via HKAnchoredObjectQuery if a future view wants them. The marginal cost is one decoded field + one dict entry per workout; the alternative — re-syncing from Strava when we realize we want a field — is much more expensive. Specifically: cycling power (`average_watts`/`max_watts`/`weighted_average_watts`/`kilojoules`), cadence, device name, and `stravaActivityId` (lets us trace any HK workout back to its Strava source).

Deliberately skipped:
- **Weather** — Strava exposes `HKMetadataKeyWeather*` candidates but populates them inconsistently; conditional decode complexity isn't worth it until Tom has a use case.
- **`gear_id`** — Strava-internal reference; useless without resolving names.
- **Splits / segments / laps / `HKWorkoutEvent`s** — over-scope per the open question at the bottom.

### HR streams: per-sample samples or downsampled?

Strava returns one HR sample per second of activity. For a 60-minute ride that's 3600 samples. HK can absolutely hold that — Apple Watch native workouts write at the same cadence — but each sample is an `HKQuantitySample` save call (or one batched save). Decision: **write at native cadence** (1Hz, one sample per second offset from start). Matches what Apple Watch produces, makes the app-authored workout indistinguishable from a native one in the Fitness app's HR graph. Single batched `save([HKQuantitySample])` call per workout to keep HK writes cheap.

### Data ownership tradeoff: accepted

HKWorkouts the app authors disappear if the app is uninstalled. Strava remains upstream; recovery path is "re-enable Strava native HK sync, accept one round of dedup." Tom confirmed acceptable.

### Tiebreaker removal scope

Drop `pelotonBundleID`/`stravaBundleID` constants, the `bundleID` field on `WorkoutCandidate`, and `Matching.swift:67-72`'s special-case branch. No "keep it around for safety during transition" — the constants stop matching as soon as Strava→HK is off, and leaving dead code violates the karpathy-guidelines simplicity-first principle. The POC bundle-ID values are still recoverable from #12's post-mortem and the git log if a future feature needs them.

### Activity-type mapping unchanged

`Matching.hkActivityType(forStravaSportType:)` is the canonical Strava-sport → HK-type map. The new no-match-create path uses the same map. Sport types not in the map (Yoga, WeightTraining, etc.) → still skipped, since we don't know what HK type to create. They were already `.skippedNoMatch` before this change; they remain `.skippedNoMatch` after.

### Status case for the new path

Add a distinct case so the UI shows whether each activity was matched-and-attached vs created-and-attached. Easier to debug "wait, why is this in HK twice" if it ever happens, and gives Tom a quick read on how many activities are flowing through which side.

Tentative: extend `ItemStatus.written(effort:)` to `.written(effort:, createdNew:)`, or split into two cases. Pick at implementation time.

## Implementation order

1. Expand HK share-authorization to include `HKWorkoutType` and `HKQuantityType(.heartRate)`. Verify the iOS permission re-prompt fires on next launch.
2. `StravaClient.fetchActivityDetail(id:)` + decode-test against fixture JSON.
3. `StravaClient.fetchActivityStreams(id:, keys:)` + decode-test against fixture JSON (keyed-by-type response shape).
4. `HealthKitManager.writeWorkout(...)` that builds an `HKWorkout` from a `StravaActivity` + detail fields + HR-stream samples per the field mapping in `In` scope above. Round-trip test: save, query back, assert core fields + metadata dict (first-class keys + custom keys present when source fields non-nil) + HR sample count.
5. `SyncOrchestrator.process` no-match branch: fetch detail → fetch streams → create workout → write HR samples → attach effort. New status case.
6. Rip Peloton/Strava tiebreaker + `WorkoutCandidate.bundleID` + bundle-ID constants. Update existing tests.
7. Tests for the no-match-create path: outdoor-ride fixture with HR stream (Strava-only), Peloton-twinned fixture (unchanged path), unmapped-sport-type fixture, missing-sufferScore fixture, no-HR-stream fixture (activity without paired HR).
8. User walkthrough to disable Strava→HK (issue body).
9. Manual verification on real device per the issue checklist.

## Test fixtures needed

- `StravaActivity` JSON: outdoor ride with HR summary + distance + elevation, no Peloton twin within ±60s window.
- `StravaActivity` JSON: Peloton-twinned ride (Watch-paired HR also in HK).
- `StravaActivity` JSON: sport_type not in the mapping (`Yoga`).
- `StravaActivity` JSON: `suffer_score == null`.
- Detail-endpoint JSON for the same activities (adds `calories`).
- Streams-endpoint JSON: typical outdoor ride (3600+ HR samples at 1Hz).
- Streams-endpoint JSON: activity with no heartrate stream (response shape when the key isn't available — verify decoder degrades to "no HR samples to write" without crashing).
- Mock HK store that records `save(HKWorkout)` and `save([HKQuantitySample])` calls so the create path is unit-testable without an HKHealthStore.

## Open questions

- **`HKWorkoutEvent` data** (segments, pauses) for created workouts: probably none for v1. The Strava list endpoint doesn't expose laps; the detail endpoint has `splits_metric` but mapping to HKWorkoutEvent is over-scope.
- **Exact Strava-app menu path** for disabling native HK sync. The walkthrough has the steps as of 2026-05-24 but Strava reorganizes settings periodically — Tom to confirm at implementation time and the issue's walkthrough section gets updated if the path drifts.
