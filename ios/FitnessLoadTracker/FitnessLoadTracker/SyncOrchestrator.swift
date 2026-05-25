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
        case writtenAsNew(effort: Double)
        case skippedNoSufferScore
        case skippedNoMatch
        case skippedMultipleMatches
        case skippedAlreadyHasEffort
        case error(String)
    }

    struct Item: Identifiable, Equatable {
        let id: Int64
        let activity: StravaActivity
        var status: ItemStatus
    }

    var items: [Item] = []
    var isSyncing = false
    var errorMessage: String?
    // Set in the defer of syncActivities/syncSingleActivity; nil until any
    // sync has finished this session. The UI uses this to distinguish
    // "no sync yet" from "sync ran and found nothing" (#24).
    var lastSyncFinishedAt: Date?

    private let client: StravaClient

    init(client: StravaClient = StravaClient()) {
        self.client = client
    }

    func syncRecentActivities(
        source: SyncLogEntry.Source,
        healthKit: HealthKitManager
    ) async {
        let after = SyncWindow.resolveAfterDate(lastSuccessfulSyncAt: SyncCheckpoint.load())
        await syncActivities(after: after, source: source, healthKit: healthKit)
    }

    // One-shot multi-page backfill from an explicit start date. Same wire
    // and side-effect surface as syncRecentActivities — just a different
    // after-date and (implicitly via fetchActivities pagination) a
    // potentially much larger result set.
    func syncBackfill(
        after: Date,
        source: SyncLogEntry.Source,
        healthKit: HealthKitManager
    ) async {
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
        lastSyncFinishedAt = nil
        defer {
            let perItemErrors = items.filter {
                if case .error = $0.status { return true }
                return false
            }.count
            let finishedAt = Date()
            SyncLog.append(SyncLogEntry(
                id: UUID(),
                timestamp: finishedAt,
                source: source,
                activitiesProcessed: items.count,
                errorSummary: errorMessage,
                perItemErrors: perItemErrors
            ))
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
        lastSyncFinishedAt = nil
        defer {
            let perItemErrors = items.filter {
                if case .error = $0.status { return true }
                return false
            }.count
            let finishedAt = Date()
            SyncLog.append(SyncLogEntry(
                id: UUID(),
                timestamp: finishedAt,
                source: source,
                activitiesProcessed: items.count,
                errorSummary: errorMessage,
                perItemErrors: perItemErrors
            ))
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
            let workouts = try await healthKit.workouts(in: start...end)
            let candidates = workouts.map {
                WorkoutCandidate(
                    startDate: $0.startDate,
                    duration: $0.duration,
                    activityType: $0.workoutActivityType
                )
            }
            switch Matching.findMatch(for: activity, in: candidates) {
            case .matched(let i):
                let workout = workouts[i]
                if try await healthKit.hasEffortScore(for: workout) {
                    items[itemIndex].status = .skippedAlreadyHasEffort
                } else {
                    try await healthKit.writeEffort(effort, on: workout)
                    items[itemIndex].status = .written(effort: effort)
                }
            case .noMatch:
                // Matching.findMatch returns .noMatch for two distinct reasons:
                // (1) sport type isn't in the HK activity-type map; we can't
                // create a workout either, so stay skipped.
                // (2) sport type is mapped but no HK twin exists within
                // tolerance — this is the create-and-attach path.
                guard Matching.hkActivityType(forStravaSportType: activity.sportType) != nil else {
                    items[itemIndex].status = .skippedNoMatch
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
}
