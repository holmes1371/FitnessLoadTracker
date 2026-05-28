# 2026-05-28 — #35 closed (BG sync skips when device locked)

- **#32's instrumentation paid off.** BG ⚠ rows surfaced "Protected health data is inaccessible" = `HKError.errorDatabaseInaccessible`: HealthKit is unreadable while the device is locked, and a `BGAppRefreshTask` can fire on a locked phone. Intermittent, purely lock-state-at-fire-time.
- **Latent bug behind the noise:** checkpoint advance only checks top-level `errorMessage`, but protected-data failures are per-item, so a locked fire failed every activity yet still advanced `SyncCheckpoint` — risking silently-skipped activities.
- **Fix.** One guard at the top of `BackgroundSync.handle()`: `guard UIApplication.shared.isProtectedDataAvailable else { task.setTaskCompleted(success: true); return }` (+ `import UIKit`). Locked fire = clean no-op, no Strava call, no checkpoint advance; retries on next unlocked fire. Rejected promoting to a top-level error (would waste the Strava fetch + trip the FailureNotifier streak).
- **#35 closed.** Tom shipping on trust, watching BG rows for a couple days; post-mortem in `completed/35.md`; PR raised with `Closes #35`.
