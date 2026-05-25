# 2026-05-25 — #30 closed (empty-state shows previous-sync time, not just-completed)

- **Bug surfaced during #24 verification.** After Sync at T2 with 0 new activities, empty-state message read "No new activities since T2" instead of "since T1". Race in `SyncOrchestrator.syncActivities`'s `defer`: `SyncCheckpoint.save(finishedAt)` runs before SwiftUI re-renders, so `ContentView.emptySyncMessage`'s `SyncCheckpoint.load()` reads the just-advanced checkpoint.
- **Fix.** `SyncOrchestrator` adds `var priorCheckpoint: Date?` set in `syncRecentActivities` to `SyncCheckpoint.load()` BEFORE the window is computed. `ContentView.emptySyncMessage` reads `sync.priorCheckpoint` instead of `SyncCheckpoint.load()`. Two-file change, no test infrastructure churn.
- **Branched off origin/main (fdbe5ef)** on `claude/30-prior-checkpoint` from this worktree, working tree was clean post-merge. The merged PR is gone so a follow-up commit on `claude/magical-almeida-fd9a65` isn't an option — exactly the failure mode CLAUDE.md warns about.
- **#30 closed.** Verified on the working branch; post-mortem in `completed/30.md`; PR raised with `Closes #30`.
