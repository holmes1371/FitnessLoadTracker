# Strava ↔ WorkOutDoors sync-timing duplicate race

## Problem

WorkOutDoors (and any watch-recorded source: Apple Watch native, Peloton) is a
**true source app** — it writes its `HKWorkout` straight into HealthKit. The
same ride also reaches Strava independently, and the two writes are not ordered:
WorkOutDoors' upload to Strava frequently beats the watch→phone HealthKit sync
(HK only lands on the phone once the watch syncs; the Strava upload only needs
connectivity).

A FitnessLoadTracker sync that runs in that gap — especially the hourly
background fire — fetches the Strava activity, finds **no HK twin yet** in the
±5min window, and takes the `.noMatch` → create path
([`SyncOrchestrator.process`](../ios/FitnessLoadTracker/FitnessLoadTracker/SyncOrchestrator.swift)
lines ~275-311), authoring its own full `HKWorkout` (status `.writtenAsNew`).
When WorkOutDoors' real workout lands later, the ride exists in HealthKit
**twice**: the native copy (with Apple Watch HR) plus our created copy.

### Why nothing reconciles them after the fact

Once both copies exist, neither the matcher nor #39's duplicate detector can
pair them, for the *same* root cause documented in `completed/37.md`:

- Our created workout stores `moving_time` as its duration; WorkOutDoors stores
  roughly `elapsed_time`.
- `Matching.findMatch` requires duration within **±60s** (`Matching.swift:48`).
  For any ride with stops, the `moving_time`/`elapsed_time` gap exceeds 60s, so
  the strict matcher rejects the pair.
- #39's `DuplicateDetection` clusters on the **same ±60s duration rule**, so it
  won't group them either — the duplicate silently persists, unflagged.

So "the duplicate match didn't work" and "the BG fired before the HK twin
existed" are not two competing explanations — they are one chain: the create
path fires early, and the duration mismatch then makes the result structurally
irreconcilable.

### How to confirm a given instance

- **Health.app → the duplicate → Source.** A copy whose source is
  **"FitnessLoadTracker"** is the create-path race (we authored it). Two foreign
  sources instead = genuine cross-app dupe (#39 territory, out of scope here).
- **App → Recent syncs → expand the ride's row.** Outcome **"Created + Effort N"**
  (`.writtenAsNew`) confirms the create path ran. Note the log keeps only the
  last 10 sync attempts (`SyncLog.maxEntries`), so check soon after the event.

## Decision

Three coupled changes, all anchored on the `.noMatch` create branch of
`process()`. **A** and **B** *prevent* the duplicate; **C** *cleans up* one
that already exists. They share the same start-time-proximity primitive, so they
are designed together even if shipped as separate slices.

### A — Grace period before creating

In the create branch, if the activity **ended less than `createGracePeriod` ago**
and no HK twin was found, **defer** instead of creating: stamp a new
`.deferredAwaitingHKTwin` status and write nothing. The 24h overlap window
(`SyncWindow.defaultOverlap`) re-fetches the activity on the next sync, by which
time the source app has almost certainly written its workout to HK → it matches
(or B catches it) normally.

- **Cost:** a genuinely Strava-only ride (one that will *never* get an HK twin)
  gets its effort/distance a few hours late instead of immediately. Acceptable
  at Tom's volume.
- **`createGracePeriod` — tentative 6h.** The watch→phone HK sync is usually
  minutes once the watch is near an unlocked phone, but can stretch to hours if
  the watch stays on-wrist away from the phone. 6h is a starting default; revisit
  after watching it in the wild. **Needs Tom's sign-off on the value.**
- "Ended" = `activity.startDate + elapsed_time`, compared against `now`.
- A real Strava-only ride **older** than the grace period still creates normally
  — the grace period only gates *recent* no-twin activities.

### B — Start-time-only suppression of the create path

Before creating, suppress if **any** non-proxy HK workout of the target activity
type starts **within ±60s** of the Strava start, *regardless of duration*. This
catches the case where the twin **is** present but the strict duration test
(`moving_time` vs `elapsed_time`) rejected it.

- Rule among non-proxy candidates of the target type starting within ±60s:
  exactly one → route through `handleMatchedWorkout` (attach effort + distance to
  the native twin, the desired matched behavior); more than one →
  `.skippedMultipleMatches`; zero → fall through to A, then create.
- **Keep the strict matcher unchanged for primary `.matched` routing.** B is a
  *looser gate applied only after the strict matcher returns `.noMatch`*.
  Broadening the global matcher's duration tolerance risks mis-pairing genuinely
  distinct back-to-back workouts; layering a start-only suppression on top of the
  strict matcher is the safer split.
- B handles "watch synced late but is now present"; A handles "watch hasn't
  synced yet at all." Together they close the race from both sides.

### C — Self-heal an existing duplicate

When a native twin and an app-authored copy of the **same** ride both exist,
delete **our** copy and ensure effort lives on the native twin. We are allowed to
delete our own workout — #12 only blocks deleting *other apps'* samples, and
#37's cleanup tool already deleted app-authored duplicates this exact way.

Reliability is the whole point (Tom's explicit ask), so the deletion is fenced by
a hard contract — **all** must hold before anything is deleted:

1. The candidate-for-deletion was **authored by this app** (`sourceName` ==
   our app) **and** carries the **exact `stravaActivityId`** currently being
   processed. (Never delete by heuristic alone.)
2. It is **not** a distance proxy (`isDistanceProxy` == false — proxies have
   their own lifecycle).
3. A **qualifying native twin exists**: a *foreign-sourced* workout of the same
   activity type starting within ±60s of the Strava start. No qualifying twin →
   **do not delete** (this protects a legitimately Strava-only ride that we
   correctly created earlier — it has no native twin and must survive).
4. **Effort is on the native twin first.** Attach effort to the native twin
   (if missing) *before* deleting our copy, so the score is never lost in the gap.
5. Deletion removes our copy **and its associated samples** (HR / energy /
   distance) — #37 noted that deleting only the workout shell orphans samples
   that keep double-counting in the data-type rollups.

- **Where it runs:** as a reconciliation step on the native-match path (strict
  `.matched` *and* B's start-suppression). After we've identified the native
  twin and ensured effort on it, look for an app-authored copy of this
  `stravaActivityId` in the window and, if the contract holds, delete it.
- **Idempotent:** after deletion, later syncs find only the native twin → normal
  match. Re-running C is a no-op (no app-authored copy left to delete).
- **Precedence (locked):** a native twin **always wins** over our app-authored
  copy. So the `.noMatch` branch must check for a native twin (strict match, then
  B) *before* the existing "dedup by our own `stravaActivityId`" step that
  currently attaches effort to our copy — otherwise we'd keep ours and never heal.

## Scope

### In

- **A:** `createGracePeriod` constant + recency gate in the create branch; new
  `ItemStatus.deferredAwaitingHKTwin` + its `summaryLabel` ("Deferred (awaiting
  HK)") and `isWrite == false`.
- **B:** a pure start-time-proximity suppression check (testable without
  `HKWorkout`, mirroring the `Matching` / `DistanceEnrichment` pure-gate pattern)
  applied in the create branch; reuse `handleMatchedWorkout` for the single-twin
  case, `.skippedMultipleMatches` for the multi case.
- **C:** `HealthKitManager.deleteWorkoutWithSamples(_:)` (workout + associated
  HR/energy/distance samples, app-authored guard inside); a native-twin lookup;
  the fenced reconciliation in `process()`; new `ItemStatus.healedDuplicate(effort:)`
  (or fold into the matched status with a flag) + `summaryLabel`
  ("Removed dup + Effort N"); `isWrite` treatment TBD at implementation.
- **Ordering rework** of the `.noMatch` branch per the precedence note above.
- **Tests:** pure gates for A (recency truth table) and B (start-proximity:
  zero / one / many twins; type mismatch; proxy excluded). C's HK-touching pieces
  follow the project pattern (pure decision logic unit-tested; the HK delete
  itself verified on-device), but the **pair-identification predicate** (contract
  items 1-3) should be a pure, unit-tested function given the deletion risk.
- **Manual-verification checklist** on the issue (real-device, see issue body).

### Out (deferred)

- **Cross-app duplicates from sources we don't own** (two foreign apps writing
  the same ride) — that's #39's read-only display case; deletion is blocked by
  #12. Unchanged here.
- **Broadening the global matcher** to reconcile `moving_time`/`elapsed_time`
  generally — a separate design question (noted as out-of-scope in `completed/37.md`).
  A/B/C work around it locally; they don't fix the underlying duration model.
- **Push/notification when a heal happens** — the Recent syncs status line is
  enough for v1; revisit if Tom wants louder signal.
- **A wide historical scan** to heal dupes outside the recent sync window — like
  #39's deferred wide-scan, possible follow-up; A/B/C only touch rides in the
  windows actually synced.

## Locked decisions

- **A + B + C ship as one feature, three internal workstreams.** They share the
  start-proximity primitive and the rewritten `.noMatch` ordering; splitting them
  across issues would fragment that shared core. May still land as separate
  commits / PR slices on the one branch.
- **Strict matcher stays strict; B is a separate looser gate.** (See B.)
- **Native twin wins; heal deletes our copy, never the foreign one.** (See C.)
- **C never deletes without a qualifying native twin present** — protects
  legitimate Strava-only creations. (Contract item 3.)
- **Detection stays source-agnostic.** No hardcoded "WorkOutDoors" / device
  names — same principle as #37's "lacks native distance, not is-Peloton."
  WorkOutDoors is the motivating case but the fix keys on *app-authored +
  stravaActivityId* vs *foreign source*, so Apple Watch native / Peloton races
  are covered identically.

## Implementation order

1. **B's pure gate** + tests (start-proximity suppression decision).
2. **A's recency gate** + `deferredAwaitingHKTwin` status + tests.
3. Rewrite the `.noMatch` branch ordering: native strict match → B → (existing
   own-id dedup, now only when no native twin) → A defer → create.
4. **C:** pair-identification predicate (pure, tested) → `deleteWorkoutWithSamples`
   → reconciliation hook on the native-match path → `healedDuplicate` status.
5. Update `SyncOrchestrator` status labels in `ContentView`.
6. Manual verification on device (issue checklist): force the race, confirm
   defer→later-match, confirm heal of a pre-existing dupe, confirm a real
   Strava-only ride still creates and is **not** deleted.

## Test fixtures needed

- Strava activity (cycling, with `suffer_score`) whose HK window has **no twin**
  and ended **< grace period** ago → expect `deferredAwaitingHKTwin` (A).
- Same, ended **> grace period** ago, no twin → expect create (A boundary).
- HK window with a **foreign twin starting within ±60s but duration off by >60s**
  (the `moving_time`/`elapsed_time` case) → expect B suppression → matched.
- HK window with **two** foreign twins within ±60s → expect `multipleMatches` (B).
- HK window with **both** a foreign twin and an app-authored copy (our
  `stravaActivityId`) → expect heal: effort on twin, app copy deleted (C).
- HK window with an app-authored copy and **no** foreign twin → expect **no
  deletion** (C contract item 3 — the legitimate Strava-only case).
- A distance proxy present in the window → never treated as a twin and never
  deleted (B + C proxy exclusion).

## Open questions

- **`createGracePeriod` value** — tentative 6h; Tom to confirm. Could be made a
  hidden constant first, surfaced as a setting only if it needs tuning.
- **`isWrite` for `healedDuplicate`** — does a heal-that-also-attached-effort
  count toward the "synced" headline (#41)? Lean yes (effort was written), decide
  at implementation.
- **Distance proxy after a heal** — if our deleted copy was an outdoor ride it
  carried baked-in distance, gone with it; the native twin (WorkOutDoors outdoor)
  carries its own native distance, so no proxy is needed. Confirm no orphaned
  proxy survives a heal in the indoor edge case.
</content>
</invoke>
