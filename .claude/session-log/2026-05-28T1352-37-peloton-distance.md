# 2026-05-28 — #37 closed (indoor-ride cycling distance)

- **Peloton indoor rides lacked HK cycling distance**; can't attach to the Peloton-owned workout (#12 ownership rule), so we author a **1-second sibling cycling "proxy" workout** carrying Strava's distance — it rolls into Cycling Workouts → Distance; 1s keeps TIME/Exercise-minutes negligible.
- Only fires when the matched cycling workout **lacks native distance** (`workoutHasNativeCyclingDistance` guard) — outdoor rides and Peloton rides that already have distance are skipped, so no duplicate distance.
- **Duplicate-workout bug** (Tom saw two of each outdoor ride): create path had no Strava-id dedup, and app-created workouts can't re-match (store `moving_time`, Matching compares `elapsed_time`); 2-yr backfill mass-produced dupes. Fixed by create-path id-dedup; one-time cleanup tool swept the existing ones.
- **Migration tools removed** after use — "Backfill 2 years" + "Remove duplicate workouts" buttons + backing code gone; cleanup-only readTypes reverted (kept `distanceCycling` read). UI back to just "Sync now".
- Full post-mortem in `completed/37.md`; XCTest pack green; PR raised with `Closes #37`.
