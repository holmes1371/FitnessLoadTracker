# 2026-05-24 — Sort synced activities newest-first in UI

- One-line tweak in `SyncOrchestrator.syncRecentActivities`: sort the fetched Strava activities by `startDate` descending before mapping to `items`, so `ContentView.syncResults` renders newest-first after the Sync button is pushed.
- Sorted at the source (not the view) so `items` is semantically ordered for any future consumer and avoids re-sorting on every SwiftUI body re-eval.
- No GitHub issue — direct ask from Tom; no `completed/*.md` artifact.
- No regression test added (pure UI ordering, no behavioral branch). Existing matching/effort tests are order-independent.
