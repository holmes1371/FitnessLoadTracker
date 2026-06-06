//
//  SyncOrchestrator.swift
//  FitnessLoadTracker
//

import Foundation
import HealthKit
import Observation

@Observable
final class SyncOrchestrator {
    enum ItemStatus: Equatable {
        case pending
        case written(effort: Double)
        case writtenWithDistance(effort: Double)
        case addedDistance
        case writtenAsNew(effort: Double)
        // The native twin was missing at create time and the ride is recent, so
        // we deferred rather than author a duplicate; the overlap window re-fetches
        // it once the source app writes its workout to HK (#43, workstream A).
        case deferredAwaitingHKTwin
        // A pre-existing app-authored copy was deleted because the source app's
        // native twin landed; effort lives on the twin (#43, workstream C).
        case healedDuplicate(effort: Double)
        case skippedNoSufferScore
        case skippedNoMatch
        case skippedMultipleMatches
        case skippedAlreadyHasEffort
        case error(String)

        // True only for the outcomes that actually wrote something to
        // HealthKit. Drives the "synced" headline count in Recent syncs (#41):
        // skips and errors don't count as synced.
        var isWrite: Bool {
            switch self {
            case .written, .writtenWithDistance, .addedDistance, .writtenAsNew, .healedDuplicate:
                return true
            default:
                return false
            }
        }

        // Plain-text, color-free outcome label persisted into the SyncLog so an
        // expanded Recent syncs row reads the same vocabulary as the live list
        // (#41). The live `statusLabel(for:)` keeps its own colored Text.
        var summaryLabel: String {
            switch self {
            case .pending: return "…"
            case .written(let effort): return String(format: "Effort %.0f", effort)
            case .writtenWithDistance(let effort): return String(format: "Effort %.0f + dist", effort)
            case .addedDistance: return "+ Distance"
            case .writtenAsNew(let effort): return String(format: "Created + Effort %.0f", effort)
            case .deferredAwaitingHKTwin: return "Deferred (awaiting HK)"
            case .healedDuplicate(let effort): return String(format: "Removed dup + Effort %.0f", effort)
            case .skippedNoSufferScore: return "No score"
            case .skippedNoMatch: return "No match"
            case .skippedMultipleMatches: return "Multiple matches"
            case .skippedAlreadyHasEffort: return "Already has effort"
            case .error(let msg): return msg
            }
        }
    }

    struct Item: Identifiable, Equatable {
        let id: Int64
        let activity: StravaActivity
        var status: ItemStatus
    }

    var items: [Item] = []
    // Possible duplicate HealthKit workouts found while syncing — surfaced for
    // manual review/deletion (#39). Ephemeral, like `items`; rebuilt each sync.
    var duplicateClusters: [DuplicateCluster] = []
    var isSyncing = false
    var errorMessage: String?
    // Set in the defer of syncActivities/syncSingleActivity; nil until any
    // sync has finished this session. The UI uses this to distinguish
    // "no sync yet" from "sync ran and found nothing" (#24).
    var lastSyncFinishedAt: Date?
    // Snapshot of SyncCheckpoint.load() taken at the start of the most
    // recent window-based sync, BEFORE the sync advances the checkpoint.
    // The empty-state UI reads this — not the live checkpoint — so the
    // "No new activities since [time]" message shows the previous sync's
    // time, not the just-completed sync's time (#30).
    var priorCheckpoint: Date?

    // A ride that ended less than this ago with no HK twin is deferred, not
    // created — giving the watch→phone sync time to land the source app's
    // workout so the next sync matches it instead of authoring a duplicate
    // (#43, workstream A). Hidden constant for now; revisit after live data.
    static let createGracePeriod: TimeInterval = 3 * 60 * 60

    private let client: StravaClient

    init(client: StravaClient = StravaClient()) {
        self.client = client
    }

    func syncRecentActivities(
        source: SyncLogEntry.Source,
        healthKit: HealthKitManager
    ) async {
        priorCheckpoint = SyncCheckpoint.load()
        let after = SyncWindow.resolveAfterDate(lastSuccessfulSyncAt: priorCheckpoint)
        await syncActivities(after: after, source: source, healthKit: healthKit)
    }

    private func syncActivities(
        after: Date,
        source: SyncLogEntry.Source,
        healthKit: HealthKitManager
    ) async {
        isSyncing = true
        errorMessage = nil
        items = []
        duplicateClusters = []
        lastSyncFinishedAt = nil
        defer {
            let finishedAt = Date()
            SyncLog.append(buildLogEntry(at: finishedAt, source: source))
            // Only advance the checkpoint on clean completion — per-item
            // errors don't block, since the next sync's overlap covers them.
            if errorMessage == nil {
                SyncCheckpoint.save(finishedAt)
            }
            lastSyncFinishedAt = finishedAt
            // Fire-and-forget — notification dispatch shouldn't block the
            // sync return. iOS holds the request even if we don't await.
            Task { await FailureNotifier.evaluate(log: SyncLog.recent()) }
            isSyncing = false
        }

        guard let refreshToken = Keychain.load() else {
            errorMessage = "Not connected to Strava."
            return
        }

        do {
            let tokens = try await client.refreshAccessToken(refreshToken: refreshToken)
            try Keychain.save(tokens.refreshToken)

            let activities = try await client.fetchActivities(accessToken: tokens.accessToken, after: after)
                .sorted { $0.startDate > $1.startDate }

            items = activities.map { Item(id: $0.id, activity: $0, status: .pending) }

            for index in items.indices {
                await process(itemIndex: index, healthKit: healthKit, accessToken: tokens.accessToken)
            }

            BackgroundSync.scheduleNext()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // Targeted single-activity sync for verification before full-history
    // backfill. Fetches the detail for `id`, projects to a StravaActivity
    // summary, and runs the same process() switch a normal sync would —
    // so matched/noMatch/multipleMatches routing stays consistent across
    // both entry points.
    func syncSingleActivity(
        id: Int64,
        source: SyncLogEntry.Source,
        healthKit: HealthKitManager
    ) async {
        isSyncing = true
        errorMessage = nil
        items = []
        duplicateClusters = []
        lastSyncFinishedAt = nil
        defer {
            let finishedAt = Date()
            SyncLog.append(buildLogEntry(at: finishedAt, source: source))
            // Targeted single-activity sync — do NOT advance SyncCheckpoint.
            // Checkpoint tracks "last full window scan completed cleanly";
            // a one-off fetch by ID would lose ground for the next full
            // Sync now if it bumped the watermark.
            lastSyncFinishedAt = finishedAt
            Task { await FailureNotifier.evaluate(log: SyncLog.recent()) }
            isSyncing = false
        }

        guard let refreshToken = Keychain.load() else {
            errorMessage = "Not connected to Strava."
            return
        }

        do {
            let tokens = try await client.refreshAccessToken(refreshToken: refreshToken)
            try Keychain.save(tokens.refreshToken)

            let detail = try await client.fetchActivityDetail(accessToken: tokens.accessToken, id: id)
            let activity = detail.asSummary
            items = [Item(id: activity.id, activity: activity, status: .pending)]
            await process(
                itemIndex: 0,
                healthKit: healthKit,
                accessToken: tokens.accessToken,
                preFetchedDetail: detail
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // Snapshot the current `items` into a persisted SyncLogEntry. Shared by
    // both sync paths' defer blocks so the count + per-item rules stay in one
    // place (#41 grew this past the inline duplication #32 left in place).
    private func buildLogEntry(at finishedAt: Date, source: SyncLogEntry.Source) -> SyncLogEntry {
        let perItemErrors = items.filter {
            if case .error = $0.status { return true }
            return false
        }.count
        let firstItemError: String? = items.lazy.compactMap {
            if case .error(let msg) = $0.status { return msg }
            return nil
        }.first
        // Pure-overlap re-fetches stamp `.skippedAlreadyHasEffort` and would
        // otherwise misleadingly count toward "activitiesProcessed" (#32).
        // Other skip kinds still count here — but the Recent syncs headline
        // now derives its "synced" number from `summaries` (wasWritten), not
        // this field, so a skip-only sync reads as 0 synced (#41).
        let processed = items.filter {
            if case .skippedAlreadyHasEffort = $0.status { return false }
            return true
        }.count
        let summaries = items.map {
            ItemSummary(
                id: $0.id,
                name: $0.activity.name,
                startDate: $0.activity.startDate,
                outcome: $0.status.summaryLabel,
                wasWritten: $0.status.isWrite
            )
        }
        return SyncLogEntry(
            id: UUID(),
            timestamp: finishedAt,
            source: source,
            activitiesProcessed: processed,
            errorSummary: errorMessage,
            perItemErrors: perItemErrors,
            firstItemError: firstItemError,
            items: summaries
        )
    }

    private func process(
        itemIndex: Int,
        healthKit: HealthKitManager,
        accessToken: String,
        preFetchedDetail: StravaActivityDetail? = nil
    ) async {
        let activity = items[itemIndex].activity

        guard let sufferScore = activity.sufferScore else {
            items[itemIndex].status = .skippedNoSufferScore
            return
        }
        guard let effort = Calibration.effort(forSufferScore: sufferScore) else {
            items[itemIndex].status = .skippedNoSufferScore
            return
        }

        do {
            let window: TimeInterval = 5 * 60
            let start = activity.startDate.addingTimeInterval(-window)
            let end = activity.startDate.addingTimeInterval(TimeInterval(activity.elapsedTime) + window)
            // Exclude our own distance-proxy workouts (#37) — they're cycling
            // workouts near the ride's start, and leaving them in the candidate
            // pool would risk a multipleMatches skip or attaching effort to the
            // proxy instead of the real Peloton workout.
            let workouts = try await healthKit.workouts(in: start...end)
                .filter { !healthKit.isDistanceProxy($0) }
            collectDuplicates(in: workouts, healthKit: healthKit)
            let candidates = workouts.map {
                WorkoutCandidate(
                    startDate: $0.startDate,
                    duration: $0.duration,
                    activityType: $0.workoutActivityType
                )
            }
            switch Matching.findMatch(for: activity, in: candidates) {
            case .matched(let i):
                try await handleMatchedWorkout(
                    itemIndex: itemIndex, workout: workouts[i],
                    effort: effort, activity: activity, healthKit: healthKit
                )
            case .noMatch:
                // Matching.findMatch returns .noMatch for two distinct reasons:
                // (1) sport type isn't in the HK activity-type map; we can't
                // create a workout either, so stay skipped.
                // (2) sport type is mapped but no HK twin exists within
                // tolerance — this is the create-and-attach path.
                guard let targetType = Matching.hkActivityType(forStravaSportType: activity.sportType) else {
                    items[itemIndex].status = .skippedNoMatch
                    return
                }
                let reconcileCandidates = workouts.map {
                    ReconcileCandidate(
                        startDate: $0.startDate,
                        activityType: $0.workoutActivityType,
                        isAppAuthored: healthKit.isAppAuthored($0),
                        isDistanceProxy: healthKit.isDistanceProxy($0),
                        stravaActivityId: healthKit.stravaActivityId(of: $0)
                    )
                }
                // B — a foreign twin (e.g. WorkOutDoors) may be present but was
                // rejected by the strict matcher on duration (moving_time vs
                // elapsed_time). Suppress the create path on start-proximity alone.
                let foreignTwins = CreatePathReconciliation.foreignTwinIndices(
                    in: reconcileCandidates, targetType: targetType, stravaStart: activity.startDate
                )
                if foreignTwins.count > 1 {
                    items[itemIndex].status = .skippedMultipleMatches
                    return
                }
                if foreignTwins.count == 1 {
                    let twin = workouts[foreignTwins[0]]
                    try await handleMatchedWorkout(
                        itemIndex: itemIndex, workout: twin,
                        effort: effort, activity: activity, healthKit: healthKit
                    )
                    // C — the native twin wins. If we also authored a copy of this
                    // ride on an earlier racing sync, effort is now on the twin;
                    // delete our copy + its samples so the ride stops double-counting.
                    if let ourCopy = CreatePathReconciliation.appAuthoredCopyIndex(
                        in: reconcileCandidates, targetType: targetType,
                        stravaStart: activity.startDate, stravaActivityId: activity.id
                    ) {
                        try await healthKit.deleteWorkoutWithSamples(workouts[ourCopy])
                        items[itemIndex].status = .healedDuplicate(effort: effort)
                    }
                    return
                }
                // No foreign twin. A workout we authored on a prior sync is usually
                // present here but rejected by Matching — we store moving_time as
                // the workout's duration while Matching compares elapsed_time, so
                // outdoor rides with stops fall outside the 60s tolerance. Dedup by
                // Strava id so re-syncs/backfill ensure effort on the existing
                // workout instead of creating a duplicate (#37). Reached only when
                // no native twin exists, so the twin always wins over our copy (#43).
                if let existing = workouts.first(where: { healthKit.stravaActivityId(of: $0) == activity.id }) {
                    try await handleMatchedWorkout(
                        itemIndex: itemIndex, workout: existing,
                        effort: effort, activity: activity, healthKit: healthKit
                    )
                    return
                }
                // A — defer rather than create if the ride is recent and has no HK
                // twin yet; the source app's workout has probably not synced from
                // the watch. The 24h overlap window re-fetches it next sync (#43).
                let activityEnd = activity.startDate.addingTimeInterval(TimeInterval(activity.elapsedTime))
                if CreatePathReconciliation.shouldDeferAwaitingTwin(
                    activityEnd: activityEnd, now: Date(), gracePeriod: Self.createGracePeriod
                ) {
                    items[itemIndex].status = .deferredAwaitingHKTwin
                    return
                }
                let detail: StravaActivityDetail
                if let pre = preFetchedDetail {
                    detail = pre
                } else {
                    detail = try await client.fetchActivityDetail(accessToken: accessToken, id: activity.id)
                }
                let streams = try await client.fetchActivityStreams(
                    accessToken: accessToken,
                    id: activity.id,
                    keys: ["heartrate", "time"]
                )
                let workout = try await healthKit.writeWorkout(detail: detail, streams: streams)
                try await healthKit.writeEffort(effort, on: workout)
                items[itemIndex].status = .writtenAsNew(effort: effort)
            case .multipleMatches:
                items[itemIndex].status = .skippedMultipleMatches
            }
        } catch {
            items[itemIndex].status = .error(error.localizedDescription)
        }
    }

    // Cluster the workouts in this activity's window into possible duplicates
    // (#39) and merge them into `duplicateClusters`. Per-activity windows overlap,
    // so the same pair can surface from several items — dedup by cluster id (the
    // sorted member UUIDs).
    private func collectDuplicates(in workouts: [HKWorkout], healthKit: HealthKitManager) {
        let checkable = workouts.map {
            WorkoutForDuplicateCheck(
                id: $0.uuid,
                startDate: $0.startDate,
                duration: $0.duration,
                activityType: $0.workoutActivityType,
                sourceName: healthKit.sourceName(of: $0),
                distanceMeters: healthKit.distanceMeters(of: $0)
            )
        }
        var seen = Set(duplicateClusters.map(\.id))
        for cluster in DuplicateDetection.clusters(in: checkable) where seen.insert(cluster.id).inserted {
            duplicateClusters.append(cluster)
        }
    }

    // Shared by the matched path and the create-path dedup. Effort and distance
    // are independent and each idempotent: a ride synced before #37 already has
    // effort but may still be missing distance, so the effort-dedup must not
    // short-circuit the distance write (the backfill case).
    private func handleMatchedWorkout(
        itemIndex: Int,
        workout: HKWorkout,
        effort: Double,
        activity: StravaActivity,
        healthKit: HealthKitManager
    ) async throws {
        let hadEffort = try await healthKit.hasEffortScore(for: workout)
        if !hadEffort {
            try await healthKit.writeEffort(effort, on: workout)
        }
        let wroteDistance = try await enrichDistanceIfNeeded(
            activity: activity, workout: workout, healthKit: healthKit
        )
        items[itemIndex].status = Self.matchedStatus(
            wroteEffort: !hadEffort, effort: effort, wroteDistance: wroteDistance
        )
    }

    // Author the Strava equivalent distance for an indoor ride whose HK twin
    // carries none (#37). The cheap activity-type/distance pre-checks skip the
    // HK dedup query for the common non-cycling case; the actual decision still
    // funnels through DistanceEnrichment.shouldWrite. Returns whether a sample
    // was written.
    private func enrichDistanceIfNeeded(
        activity: StravaActivity,
        workout: HKWorkout,
        healthKit: HealthKitManager
    ) async throws -> Bool {
        guard workout.workoutActivityType == .cycling, activity.distance > 0 else { return false }
        let hasNative = healthKit.workoutHasNativeCyclingDistance(workout)
        let alreadyWritten = try await healthKit.hasDistanceProxyWorkout(
            stravaActivityId: activity.id, in: workout.startDate...workout.endDate
        )
        guard DistanceEnrichment.shouldWrite(
            activityType: workout.workoutActivityType,
            stravaDistanceMeters: activity.distance,
            workoutHasNativeDistance: hasNative,
            alreadyWrittenByUs: alreadyWritten
        ) else { return false }
        try await healthKit.writeDistanceProxyWorkout(
            meters: activity.distance,
            start: workout.startDate,
            stravaActivityId: activity.id
        )
        return true
    }

    private static func matchedStatus(
        wroteEffort: Bool,
        effort: Double,
        wroteDistance: Bool
    ) -> ItemStatus {
        switch (wroteEffort, wroteDistance) {
        case (true, true):   return .writtenWithDistance(effort: effort)
        case (true, false):  return .written(effort: effort)
        case (false, true):  return .addedDistance
        case (false, false): return .skippedAlreadyHasEffort
        }
    }
}
