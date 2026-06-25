# 2026-06-25 — #49 closed (removed #37 distance-proxy enrichment)

- **#37's 1s distance proxy double-counts**: Peloton backfills native distance onto its own ride when its app is next opened, so proxy + native both land for the same ride; removed the proxy write path — native Peloton distance is better data and arrives unaided.
- Removed `DistanceEnrichment` (+tests), `enrichDistanceIfNeeded`/`matchedStatus`, `writeDistanceProxyWorkout`/`hasDistanceProxyWorkout`/`workoutHasNativeCyclingDistance`, the `writtenWithDistance`/`addedDistance` statuses, and `StravaActivity.distance`; matched cycling path now writes **effort only**.
- **Kept** `isDistanceProxy` + `distanceProxyMetadataKey` and the matcher/#43 proxy-exclusion guards — legacy proxies persist in HealthKit until Tom deletes them manually (no cleanup tool built; his call).
- Off-script flow: filed + coded from iPhone in remote container, verified on Mac via a hand-pulled worktree + manual `ios/.env` symlink; confirmed secrets don't leak (`*.env` gitignored, committed `Secrets.swift` empty, push from never-built container).
- Full post-mortem in `completed/49.md`; XCTest green on-device; PR raised with `Closes #49`.
