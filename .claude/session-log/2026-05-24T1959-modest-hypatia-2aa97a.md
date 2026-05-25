# 2026-05-24 — Plan #17: single-writer HK pipeline

- Filed [#17](https://github.com/holmes1371/FitnessLoadTracker/issues/17) (Todo column): eliminate Peloton/Strava HK duplicates at the source by disabling Strava's native HK sync and having the app create HKWorkouts (with per-second HR from `/streams`) for Strava-only activities. Full scope locked in `design/strava-hk-single-writer.md`.
- No code this session — design + filing only. PR carries the design note + this session-log; `Refs #17`, not `Closes`.
- Implementation order is the 9-step list at the bottom of the design note; first step is expanding HK share-auth to include `HKWorkoutType` + `.heartRate`.
- Auto-mode held the Todo → In Progress move pending explicit "start coding" approval — tomorrow's agent should make that move at the top of the implementation session.
- Vestigial to rip alongside the new code: `Matching.swift:67-72` Peloton-over-Strava tiebreaker + `WorkoutCandidate.bundleID` + the two bundle-ID constants. Reasoning lives in the design note's "Locked decisions."
