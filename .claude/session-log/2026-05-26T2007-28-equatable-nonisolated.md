# 2026-05-26 — #28 closed (Swift 6 main-actor Equatable warnings)

- **Pre-existing 16 warnings** about `Equatable` conformances being main-actor-isolated, surfaced during #24's verification. Root cause: project's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` makes every type implicitly `@MainActor`, and Swift Testing assertions run nonisolated.
- **Fix.** Added `nonisolated` to the three offending type declarations (`SyncLogEntry`, `FailureNotifier.Decision`, `MatchResult`) — pure value types, no main-actor semantics. Three-keyword change. Global setting flip was rejected because it would un-isolate the `@Observable` classes (`HealthKitManager`/`StravaConnection`/`SyncOrchestrator`) that need to stay main-actor for SwiftUI state binding.
- **#28 closed.** Tom verified `⌘U` clean (16 → 0 warnings) on the working branch; post-mortem in `completed/28.md`; PR raised with `Closes #28`.
